require 'gitexplorer/version'
require 'thor'
require 'pipeme'
require 'logger'

module GitExplorer

  GitStatus = Struct.new("GitStatus",:status,:project_name,:branch,:files,)

  def extract_status
    -> (status_output) {
      project_name = status_output[/^(?<project_name>.*)$/, "project_name"]
      branch = status_output[/On branch\s(?<branch>.*)/, "branch"]
      status = :up_to_date unless status_output[/not staged/]
      status = :not_staged if status_output[/not staged/]
      files = status_output.scan(/modified: \s*(.*)$/).flatten
      GitStatus.new(status, project_name, branch, files)
    }
  end

  def extract_light_status(status_output)
    project_name = status_output[/^(?<project_name>.*)$/, "project_name"]
    branch = status_output[/On branch\s(?<branch>.*)/, "branch"]
    status = :up_to_date unless status_output[/not staged/]
    status = :not_staged if status_output[/not staged/]
    files = status_output.scan(/modified: \s*(.*)$/).flatten
    GitStatus.new(status, project_name, branch, files)
  end

  def extract_dir_name
    -> (dot_git_file_path) { dot_git_file_path.gsub(/\.git$/,'') }
  end

  def extract_path(line, root_dir)
    parsed_path = line[/.*\s(?<path>.*)$/, 'path']
    root_dir + parsed_path
  end

  def git_repository?(path)
    return nil if path.nil?
    is_directory = File.directory?(path)
    is_repository = run("find #{path} -maxdepth 1 -type d -name .git", config={:capture=>true, :verbose=>false}) if is_directory
    is_directory and !is_repository.empty?
  end

  def git_status(path)
    run("basename `git -C #{path} rev-parse --show-toplevel`; git -C #{path} status", config={:capture=>true, :verbose=>false})
  end

  class Explorer < Thor
    include Thor::Actions
    include GitExplorer

    Line = Struct.new('Line', :full_line, :state, :git_repository)
    LOGGER = Logger.new(STDOUT)

    desc 'use for explore one level directories and show actual status of git repositories', 'git explore .'
    def explore_light(root_dir='./')
      run("ls #{root_dir} -l | awk '{if(NR>1)print}'", config={:capture=>true, :verbose=>false})
          .split("\n")
          .map{|line| Line.new(line)}
          .map{|line| Line.new(line.full_line, '', git_repository?(extract_path(line.full_line, root_dir)))}
          .map{|line| Line.new(line.full_line, (extract_light_status(git_status(extract_path(line.full_line, root_dir))) if line.git_repository == true), line.git_repository)}
          .map{|line| say(message="#{line.full_line} #{'[' + line.state.branch + ']' unless line.git_repository == false} #{'✖' if line.git_repository == true and line.state.status != :up_to_date} #{'✔' if line.git_repository == true and line.state.status == :up_to_date}\n")}
    end

    # TODO refactor and extract maps to lambdas
    desc 'use for explore recursively directories and show actual status of git repositories', 'git explore .'
    def explore(root_dir='./')
      run("find #{root_dir} -type d -name .git", config={:capture=>true, :verbose=>false})
          .split("\n")
          .map{|file| file >> extract_dir_name}
          .map{|dir| run("basename `git -C #{dir} rev-parse --show-toplevel`; git -C #{dir} status", config={:capture=>true, :verbose=>false})}
          .map{|status| status >> extract_status}
          .map{|status| say(message="#{status.project_name} is #{status.status} on branch #{status.branch}\n#{status.files.map{|f| "\t#{f}\n"}.join}", color=(:red if status.status.equal?(:not_staged)))}
    end

  end
end
