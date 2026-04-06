module GitExplorer
  class FormatRenderer
    DEFAULT_CURRENT_FORMAT = "$status $project $currentBranch main:$mainBranch sync:$sync".freeze
    DEFAULT_EXPLORE_FORMAT = "$project $statusText branch:$currentBranch main:$mainBranch sync:$sync".freeze
    DEFAULT_LIGHT_FORMAT = "[$currentBranch|$mainBranch|$sync] $status".freeze

    TOKEN_MAP = {
      "status" => ->(repo) { repo.status_symbols },
      "statusText" => ->(repo) { repo.status_text },
      "project" => ->(repo) { repo.project_name },
      "path" => ->(repo) { repo.path },
      "currentBranch" => ->(repo) { repo.current_branch },
      "mainBranch" => ->(repo) { repo.default_branch },
      "defaultBranch" => ->(repo) { repo.default_branch },
      "sync" => ->(repo) { repo.sync_state },
      "remote" => ->(repo) { repo.remote_url.to_s },
      "host" => ->(repo) { repo.remote_host.to_s },
      "owner" => ->(repo) { repo.owner.to_s },
      "ownerType" => ->(repo) { repo.owner_type.to_s }
    }.freeze

    def initialize(format, styler: AnsiStyler.new(enabled: false))
      @format = format
      @styler = styler
    end

    def render(repository_status)
      template = @format.gsub("$$", "\0")

      rendered = template.gsub(/\$(\w+)/) do |match|
        token = Regexp.last_match(1)
        value = token_value(token, repository_status)
        value.nil? ? match : style_token(token, value, repository_status)
      end

      rendered.gsub("\0", "$").rstrip
    end

    def self.needs_owner_type?(format)
      format.to_s.match?(/\$(ownerType)\b/)
    end

    private

    def token_value(token, repository_status)
      handler = TOKEN_MAP[token]
      handler&.call(repository_status)
    end

    def style_token(token, value, repository_status)
      case token
      when "status", "statusText"
        @styler.apply(value, repository_status.status_style)
      when "project"
        @styler.apply(value, :bold)
      when "path", "remote"
        @styler.apply(value, :faint)
      when "host"
        @styler.apply(value, :cyan)
      when "currentBranch"
        @styler.apply(value, *current_branch_styles(repository_status))
      when "mainBranch", "defaultBranch"
        @styler.apply(value, :blue)
      when "sync"
        @styler.apply(value, sync_style(repository_status.sync_state))
      when "ownerType"
        @styler.apply(value, owner_type_style(repository_status.owner_type))
      when "owner"
        @styler.apply(value, owner_type_style(repository_status.owner_type))
      else
        value
      end
    end

    def current_branch_styles(repository_status)
      return [:magenta] if repository_status.detached?
      return [:green] if repository_status.current_branch == repository_status.default_branch

      [:yellow]
    end

    def sync_style(sync_state)
      case sync_state
      when "in-sync" then :green
      when "ahead", "behind" then :yellow
      when "diverged" then :red
      when "detached" then :magenta
      else :faint
      end
    end

    def owner_type_style(owner_type)
      case owner_type
      when "company" then :blue
      when "personal" then :green
      else :faint
      end
    end
  end
end
