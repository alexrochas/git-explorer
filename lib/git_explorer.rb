require "gitexplorer/version"
require "thor"

# TODO extract to a separated gem
class Object
  def >>(proc)
    proc.(self)
  end
end

module GitExplorer

  GitStatus = Struct.new("GitStatus",:status,:branch,:files,)

  def self.extract_status
    -> (status_output) {
      branch = status_output[/On branch\s(?<branch>.*)/, "branch"]
      status = :up_to_date unless status_output[/not staged/]
      status = :not_staged if status_output[/not staged/]
      files = status_output.scan(/modified: \s*(.*)$/).flatten
      GitStatus.new(status, branch, files)
    }
  end

  class Explorer < Thor
    include Thor::Actions

    # TODO receive root path by parameter
    # TODO refactor and extract maps to lambdas
    desc "use for explore recursively directories and show actual status of git repositories", "gitx explore ."
    def explore
      run("find ./ -type f -name .gitignore", config={:capture=>true})
          .split("\n")
          .map{|file| file.gsub(/\.gitignore/,'')}
          .map{|dir| run("git -C #{dir} status", config={:capture=>true})}
          .map{|status| status >> GitExplorer::extract_status}
          .map{|status| say "#{status.status} on branch #{status.branch} -> #{status.files}"}
    end

  end
end
