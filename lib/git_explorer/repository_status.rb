module GitExplorer
  class RepositoryStatus
    STATUS_ORDER = [:clean, :conflicted, :staged, :unstaged, :untracked].freeze
    STATUS_SYMBOLS = {
      clean: "✔",
      conflicted: "✖",
      staged: "✚",
      unstaged: "●",
      untracked: "?"
    }.freeze

    attr_reader :project_name,
                :path,
                :current_branch,
                :default_branch,
                :sync_state,
                :statuses,
                :changed_files,
                :remote_url,
                :remote_host,
                :owner,
                :owner_type

    def initialize(project_name:, path:, current_branch:, default_branch:, sync_state:, statuses:, changed_files:, remote_url:, remote_host:, owner:, owner_type:)
      @project_name = project_name
      @path = path
      @current_branch = current_branch
      @default_branch = default_branch
      @sync_state = sync_state
      @statuses = statuses.freeze
      @changed_files = changed_files.freeze
      @remote_url = remote_url
      @remote_host = remote_host
      @owner = owner
      @owner_type = owner_type
    end

    def clean?
      statuses == [:clean]
    end

    def status_symbols
      ordered_statuses.map { |status| STATUS_SYMBOLS.fetch(status) }.join
    end

    def status_text
      ordered_statuses.join(",")
    end

    def detached?
      current_branch.start_with?("detached@")
    end

    def status_style
      return :red if statuses.include?(:conflicted)
      return :yellow if statuses.include?(:unstaged) || statuses.include?(:untracked)
      return :cyan if statuses.include?(:staged)

      :green
    end

    private

    def ordered_statuses
      statuses.sort_by { |status| STATUS_ORDER.index(status) || STATUS_ORDER.length }
    end
  end
end
