require "find"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "uri"

module GitExplorer
  class RepositoryInspector
    GITHUB_HOSTS = ["github.com", "www.github.com"].freeze
    OWNER_TYPE_CACHE_TTL = 7 * 24 * 60 * 60

    def initialize(default_branch: nil, remote_name: "origin", fetch_remote: false)
      @default_branch_override = default_branch
      @remote_name = remote_name
      @fetch_remote = fetch_remote
      @owner_type_cache = {}
      @persisted_owner_type_cache = load_owner_type_cache
    end

    def inspect(path, include_owner_type: false)
      root = repository_root(path)
      return unless root

      fetch_remote(root) if @fetch_remote

      remote = remote_details(root)
      default_branch = resolve_default_branch(root)

      RepositoryStatus.new(
        project_name: File.basename(root),
        path: root,
        current_branch: current_branch(root),
        default_branch: default_branch || "unknown",
        sync_state: sync_state(root, default_branch),
        statuses: working_tree_statuses(root),
        changed_files: changed_files(root),
        remote_url: remote[:url],
        remote_host: remote[:host],
        owner: remote[:owner],
        owner_type: include_owner_type ? owner_type(remote) : "unknown"
      )
    end

    def recursive_repositories(root_dir, include_nested: false)
      repositories = []
      expanded_root = File.expand_path(root_dir)

      Find.find(expanded_root) do |path|
        next unless File.directory?(path)

        if File.directory?(File.join(path, ".git"))
          repositories << path
          Find.prune unless include_nested
        end
      end

      repositories.uniq.sort
    rescue Errno::EACCES
      repositories
    end

    def direct_children(root_dir)
      Dir.children(File.expand_path(root_dir)).reject { |entry| entry.start_with?(".") }.sort
    end

    def git_repository?(path)
      !repository_root(path).nil?
    end

    def list_entry(root_dir, entry)
      capture("ls", "-ld", entry, chdir: File.expand_path(root_dir)).strip
    end

    private

    def repository_root(path)
      expanded_path = File.expand_path(path)
      output = capture("git", "-C", expanded_path, "rev-parse", "--show-toplevel", allow_failure: true)
      cleaned_output = output.to_s.strip
      cleaned_output.empty? ? nil : cleaned_output
    end

    def current_branch(root)
      branch = capture("git", "-C", root, "branch", "--show-current", allow_failure: true).to_s.strip
      return branch unless branch.empty?

      commit = capture("git", "-C", root, "rev-parse", "--short", "HEAD", allow_failure: true).to_s.strip
      commit.empty? ? "HEAD" : "detached@#{commit}"
    end

    def working_tree_statuses(root)
      porcelain_entries = porcelain_entries(root)
      return [:clean] if porcelain_entries.empty?

      statuses = porcelain_entries.each_with_object([]) do |entry, values|
        code = entry[0, 2]
        index_status = code[0]
        worktree_status = code[1]

        values << :conflicted if conflicted?(code)
        values << :staged if staged?(index_status)
        values << :unstaged if unstaged?(worktree_status)
        values << :untracked if code == "??"
      end

      statuses.uniq
    end

    def changed_files(root)
      porcelain_entries(root).map do |entry|
        path_fragment = entry[3..].to_s
        path_fragment.split(" -> ").last
      end
    end

    def porcelain_entries(root)
      capture("git", "-C", root, "status", "--porcelain=1", allow_failure: true)
        .to_s
        .lines
        .map(&:chomp)
        .reject(&:empty?)
    end

    def conflicted?(code)
      %w[DD AU UD UA DU AA UU].include?(code) || code.include?("U")
    end

    def staged?(index_status)
      ![" ", "?", "U"].include?(index_status)
    end

    def unstaged?(worktree_status)
      ![" ", "?"].include?(worktree_status)
    end

    def resolve_default_branch(root)
      return @default_branch_override if @default_branch_override

      remote_head = capture("git", "-C", root, "symbolic-ref", "--quiet", "--short", "refs/remotes/#{@remote_name}/HEAD", allow_failure: true).to_s.strip
      return remote_head.delete_prefix("#{@remote_name}/") unless remote_head.empty?

      %w[main master].find do |candidate|
        ref_exists?(root, "refs/remotes/#{@remote_name}/#{candidate}") || ref_exists?(root, "refs/heads/#{candidate}")
      end
    end

    def sync_state(root, default_branch)
      return "unknown" if default_branch.to_s.empty?
      return "detached" if current_branch(root).start_with?("detached@")

      comparison_ref = if ref_exists?(root, "refs/remotes/#{@remote_name}/#{default_branch}")
                         "#{@remote_name}/#{default_branch}"
                       elsif ref_exists?(root, "refs/heads/#{default_branch}")
                         default_branch
                       end

      return "unknown" unless comparison_ref

      counts = capture("git", "-C", root, "rev-list", "--left-right", "--count", "#{comparison_ref}...HEAD", allow_failure: true).to_s.strip
      behind_count, ahead_count = counts.split.map(&:to_i)

      return "unknown" unless behind_count && ahead_count
      return "in-sync" if behind_count.zero? && ahead_count.zero?
      return "ahead" if behind_count.zero?
      return "behind" if ahead_count.zero?

      "diverged"
    end

    def ref_exists?(root, ref)
      _output, status = Open3.capture2e("git", "-C", root, "show-ref", "--verify", "--quiet", ref)
      status.success?
    end

    def remote_details(root)
      url = capture("git", "-C", root, "remote", "get-url", @remote_name, allow_failure: true).to_s.strip
      return empty_remote_details if url.empty?

      ssh_match = url.match(%r{\Agit@(?<host>[^:]+):(?<owner>[^/]+)/(?<repo>.+?)(?:\.git)?\z})
      http_match = url.match(%r{\Ahttps?://(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>.+?)(?:\.git)?/?\z})
      match = ssh_match || http_match

      return empty_remote_details.merge(url: url) unless match

      {
        url: url,
        host: match[:host],
        owner: match[:owner],
        repo: match[:repo]
      }
    end

    def empty_remote_details
      { url: nil, host: nil, owner: nil, repo: nil }
    end

    def owner_type(remote)
      return "unknown" unless GITHUB_HOSTS.include?(remote[:host]) && remote[:owner] && remote[:repo]

      cache_key = "#{remote[:owner]}/#{remote[:repo]}"
      cached = cached_owner_type(cache_key)
      return cached if cached

      payload = github_repository_payload(remote)
      resolved_type = case payload.dig("owner", "type")
                      when "Organization" then "company"
                      when "User" then "personal"
                      else "unknown"
                      end

      cache_owner_type(cache_key, resolved_type)
    rescue StandardError
      @owner_type_cache[cache_key] = "unknown"
    end

    def github_repository_payload(remote)
      uri = URI("https://api.github.com/repos/#{remote[:owner]}/#{remote[:repo]}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"

      token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
      request["Authorization"] = "Bearer #{token}" if token

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) do |http|
        http.request(request)
      end

      return {} unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def fetch_remote(root)
      return unless remote_configured?(root)

      capture("git", "-C", root, "fetch", "--quiet", @remote_name, allow_failure: true)
    end

    def remote_configured?(root)
      capture("git", "-C", root, "remote", "get-url", @remote_name, allow_failure: true).to_s.strip != ""
    end

    def capture(*command, allow_failure: false, chdir: nil)
      if chdir
        output, status = Open3.capture2e(*command, chdir: chdir)
      else
        output, status = Open3.capture2e(*command)
      end

      return output if status.success?
      return nil if allow_failure

      raise "Command failed: #{command.join(' ')}\n#{output}"
    end

    def cached_owner_type(cache_key)
      return @owner_type_cache[cache_key] if @owner_type_cache.key?(cache_key)

      entry = @persisted_owner_type_cache[cache_key]
      return unless entry.is_a?(Hash)
      return if owner_type_cache_expired?(entry)

      @owner_type_cache[cache_key] = entry["value"]
    end

    def cache_owner_type(cache_key, owner_type)
      @owner_type_cache[cache_key] = owner_type
      return if owner_type == "unknown"

      @persisted_owner_type_cache[cache_key] = {
        "value" => owner_type,
        "fetched_at" => Time.now.to_i
      }

      persist_owner_type_cache
      owner_type
    end

    def owner_type_cache_expired?(entry)
      fetched_at = entry["fetched_at"].to_i
      fetched_at.zero? || fetched_at < Time.now.to_i - owner_type_cache_ttl
    end

    def owner_type_cache_ttl
      Integer(ENV.fetch("GIT_EXPLORER_OWNER_CACHE_TTL", OWNER_TYPE_CACHE_TTL.to_s))
    rescue ArgumentError
      OWNER_TYPE_CACHE_TTL
    end

    def owner_type_cache_path
      base_dir = ENV["XDG_CACHE_HOME"] || File.join(Dir.home, ".cache")
      File.join(base_dir, "git-explorer", "owner_types.json")
    end

    def load_owner_type_cache
      path = owner_type_cache_path
      return {} unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      parsed.is_a?(Hash) ? parsed : {}
    rescue StandardError
      {}
    end

    def persist_owner_type_cache
      path = owner_type_cache_path
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(@persisted_owner_type_cache))
    rescue StandardError
      nil
    end
  end
end
