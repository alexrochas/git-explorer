require "gitexplorer/version"
require "thor"

# TODO extract to a separated gem
class Object
  def >>(proc)
    proc.(self)
  end
end

module GitExplorer

  GitStatus = Struct.new("GitStatus",:status,:project_name,:branch,:files,)

  def self.extract_status
    -> (status_output) {
      project_name = status_output[/^(?<project_name>.*)$/, "project_name"]
      branch = status_output[/On branch\s(?<branch>.*)/, "branch"]
      status = :up_to_date unless status_output[/not staged/]
      status = :not_staged if status_output[/not staged/]
      files = status_output.scan(/modified: \s*(.*)$/).flatten
      GitStatus.new(status, project_name, branch, files)
    }
  end

  class Explorer < Thor
    include Thor::Actions

    # TODO refactor and extract maps to lambdas
    desc "use for explore recursively directories and show actual status of git repositories", "gitx explore ."
    def explore(root_dir="./")
      run("find #{root_dir} -type f -name .gitignore", config={:capture=>true, :verbose=>false})
          .split("\n")
          .map{|file| file.gsub(/\.gitignore/,'')}
          .map{|dir| run("basename `git -C #{dir} rev-parse --show-toplevel`; git -C #{dir} status", config={:capture=>true, :verbose=>false})}
          .map{|status| status >> GitExplorer::extract_status}
          .map{|status| say "project #{status.project_name} is #{status.status} on branch #{status.branch} -> #{status.files}"}
    end

  end
end
