require "thor"

module GitExplorer
  class Explorer < Thor
    def self.exit_on_failure?
      true
    end

    class_option :remote, type: :string, default: "origin", desc: "Remote used to resolve the default branch and owner details"
    class_option :default_branch, type: :string, aliases: "-b", desc: "Override the branch used for sync checks"
    class_option :fetch, type: :boolean, default: false, desc: "Fetch the configured remote before computing sync data"
    class_option :color, type: :boolean, desc: "Force color output on or off. Defaults to auto-detecting TTY output."

    desc "current [PATH]", "Inspect the current repository and print a configurable one-line output"
    method_option :format, type: :string, aliases: "-f", desc: "Output template, e.g. '$status $currentBranch $mainBranch $sync $ownerType'"
    def current(path = ".")
      inspector = build_inspector
      format = options[:format] || ENV["GIT_EXPLORER_FORMAT"] || FormatRenderer::DEFAULT_CURRENT_FORMAT
      repository = inspector.inspect(path, include_owner_type: FormatRenderer.needs_owner_type?(format))

      raise Thor::Error, "No git repository found at #{File.expand_path(path)}" unless repository

      say(renderer_for(format).render(repository))
    end

    desc "explore [ROOT_DIR]", "Explore repositories recursively or decorate the direct children of a folder"
    method_option :light, type: :boolean, aliases: "-l", desc: "Decorate the root directory listing instead of recursively exploring repositories"
    method_option :nested, type: :boolean, default: false, desc: "Include repositories nested inside other repositories"
    method_option :format, type: :string, aliases: "-f", desc: "Output template for repository metadata"
    def explore(root_dir = "./")
      inspector = build_inspector

      if options[:light]
        render_light_listing(inspector, root_dir)
      else
        render_recursive_listing(inspector, root_dir)
      end
    end

    private

    def render_light_listing(inspector, root_dir)
      custom_format = options[:format] || ENV["GIT_EXPLORER_LIGHT_FORMAT"]
      format = custom_format || FormatRenderer::DEFAULT_LIGHT_FORMAT
      renderer = renderer_for(format)
      include_owner_type = FormatRenderer.needs_owner_type?(format)

      inspector.direct_children(root_dir).each do |child|
        path = File.join(File.expand_path(root_dir), child)
        entry = inspector.list_entry(root_dir, child)
        repository = inspector.inspect(path, include_owner_type: include_owner_type)

        if repository
          say("#{entry} #{renderer.render(repository)}")
        else
          say(entry)
        end
      end
    end

    def render_recursive_listing(inspector, root_dir)
      custom_format = options[:format] || ENV["GIT_EXPLORER_FORMAT"]
      format = custom_format || FormatRenderer::DEFAULT_EXPLORE_FORMAT
      renderer = renderer_for(format)
      include_owner_type = FormatRenderer.needs_owner_type?(format)

      inspector.recursive_repositories(root_dir, include_nested: options[:nested]).each do |path|
        repository = inspector.inspect(path, include_owner_type: include_owner_type)
        next unless repository

        if custom_format
          say(renderer.render(repository))
        else
          say(default_repository_summary(repository))
          repository.changed_files.each { |file| say("  #{file}") }
        end
      end
    end

    def default_repository_summary(repository)
      "#{repository.project_name} is #{repository.status_text} on branch #{repository.current_branch} (main: #{repository.default_branch}, sync: #{repository.sync_state})"
    end

    def build_inspector
      RepositoryInspector.new(
        default_branch: options[:default_branch],
        remote_name: options[:remote],
        fetch_remote: options[:fetch]
      )
    end

    def renderer_for(format)
      FormatRenderer.new(format, styler: AnsiStyler.new(enabled: color_enabled?))
    end

    def color_enabled?
      return options[:color] unless options[:color].nil?

      $stdout.tty? && ENV["NO_COLOR"].to_s.empty?
    end
  end
end
