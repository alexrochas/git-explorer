require "spec_helper"
require "tmpdir"

RSpec.describe GitExplorer do
  describe "version" do
    it "has a version number" do
      expect(GitExplorer::VERSION).not_to be_nil
    end
  end

  describe GitExplorer::FormatRenderer do
    it "renders configurable placeholders" do
      repository = GitExplorer::RepositoryStatus.new(
        project_name: "git-explorer",
        path: "/tmp/git-explorer",
        current_branch: "feature/prompt",
        default_branch: "main",
        sync_state: "ahead",
        statuses: [:staged, :unstaged],
        changed_files: ["README.md"],
        remote_url: "git@github.com:alexrochas/git-explorer.git",
        remote_host: "github.com",
        owner: "alexrochas",
        owner_type: "personal"
      )

      format = "$status $currentBranch $mainBranch $sync $ownerType $owner"
      rendered = described_class.new(format).render(repository)

      expect(rendered).to eq("✚● feature/prompt main ahead personal alexrochas")
    end

    it "removes trailing whitespace when optional tokens are empty" do
      repository = GitExplorer::RepositoryStatus.new(
        project_name: "git-explorer",
        path: "/tmp/git-explorer",
        current_branch: "main",
        default_branch: "main",
        sync_state: "in-sync",
        statuses: [:clean],
        changed_files: [],
        remote_url: nil,
        remote_host: nil,
        owner: nil,
        owner_type: "unknown"
      )

      expect(described_class.new("$project $owner").render(repository)).to eq("git-explorer")
    end

    it "can colorize rendered tokens" do
      repository = GitExplorer::RepositoryStatus.new(
        project_name: "git-explorer",
        path: "/tmp/git-explorer",
        current_branch: "feature/prompt",
        default_branch: "main",
        sync_state: "ahead",
        statuses: [:staged, :unstaged],
        changed_files: ["README.md"],
        remote_url: "git@github.com:alexrochas/git-explorer.git",
        remote_host: "github.com",
        owner: "alexrochas",
        owner_type: "personal"
      )

      styler = GitExplorer::AnsiStyler.new(enabled: true)
      rendered = described_class.new("$status $currentBranch $mainBranch $sync $ownerType", styler: styler).render(repository)

      expect(rendered).to include("\e[33mfeature/prompt\e[0m")
      expect(rendered).to include("\e[34mmain\e[0m")
      expect(rendered).to include("\e[33mahead\e[0m")
      expect(rendered).to include("\e[32mpersonal\e[0m")
    end
  end

  describe GitExplorer::RepositoryInspector do
    it "detects the checked out branch, default branch, sync status, and changes" do
      in_repo("main") do |repo_path|
        git(repo_path, "checkout", "-b", "feature/reporting")
        File.write(File.join(repo_path, "feature.txt"), "feature work\n")
        git(repo_path, "add", "feature.txt")
        git(repo_path, "commit", "-m", "Add feature")
        File.write(File.join(repo_path, "staged.txt"), "ready to stage\n")
        git(repo_path, "add", "staged.txt")
        File.write(File.join(repo_path, "README.md"), "dirty change\n")

        repository = described_class.new.inspect(repo_path)

        expect(repository.current_branch).to eq("feature/reporting")
        expect(repository.default_branch).to eq("main")
        expect(repository.sync_state).to eq("ahead")
        expect(repository.statuses).to contain_exactly(:staged, :unstaged)
        expect(repository.changed_files).to contain_exactly("README.md", "staged.txt")
      end
    end

    it "falls back to master when that is still the repository default" do
      in_local_repo("master") do |repo_path|
        repository = described_class.new.inspect(repo_path)

        expect(repository.default_branch).to eq("master")
        expect(repository.current_branch).to eq("master")
        expect(repository.sync_state).to eq("in-sync")
      end
    end

    it "returns unknown when the repository default branch cannot be resolved" do
      in_local_repo("trunk") do |repo_path|
        repository = described_class.new.inspect(repo_path)

        expect(repository.default_branch).to eq("unknown")
        expect(repository.current_branch).to eq("trunk")
        expect(repository.sync_state).to eq("unknown")
      end
    end

    it "maps GitHub owner types to personal or company" do
      in_repo("main", remote_url: "git@github.com:example/project.git") do |repo_path|
        inspector = described_class.new
        allow(inspector).to receive(:github_repository_payload).and_return({ "owner" => { "type" => "Organization" } })

        repository = inspector.inspect(repo_path, include_owner_type: true)

        expect(repository.owner_type).to eq("company")
        expect(repository.owner).to eq("example")
      end
    end

    it "can refresh the remote before computing sync" do
      in_repo("main") do |repo_path, remote_path|
        upstream_clone = File.join(File.dirname(repo_path), "upstream-work")
        git(File.dirname(repo_path), "clone", remote_path, upstream_clone)
        configure_git_identity(upstream_clone)
        File.write(File.join(upstream_clone, "upstream.txt"), "remote change\n")
        git(upstream_clone, "add", "upstream.txt")
        git(upstream_clone, "commit", "-m", "Advance main")
        git(upstream_clone, "push", "origin", "main")

        stale_repository = described_class.new.inspect(repo_path)
        fresh_repository = described_class.new(fetch_remote: true).inspect(repo_path)

        expect(stale_repository.sync_state).to eq("in-sync")
        expect(fresh_repository.sync_state).to eq("behind")
      end
    end

    it "persists owner type lookups across runs" do
      in_repo("main", remote_url: "git@github.com:example/project.git") do |repo_path|
        Dir.mktmpdir do |cache_dir|
          with_env("XDG_CACHE_HOME" => cache_dir) do
            first_inspector = described_class.new
            allow(first_inspector).to receive(:github_repository_payload).once.and_return({ "owner" => { "type" => "Organization" } })

            expect(first_inspector.inspect(repo_path, include_owner_type: true).owner_type).to eq("company")

            second_inspector = described_class.new
            expect(second_inspector).not_to receive(:github_repository_payload)

            expect(second_inspector.inspect(repo_path, include_owner_type: true).owner_type).to eq("company")
          end
        end
      end
    end

    it "skips nested repositories by default when exploring recursively" do
      Dir.mktmpdir do |tmpdir|
        root_repo = File.join(tmpdir, "root")
        nested_repo = File.join(root_repo, "vendor", "nested")

        git(tmpdir, "init", "--initial-branch=main", root_repo)
        git(tmpdir, "init", "--initial-branch=main", nested_repo)

        repositories = described_class.new.recursive_repositories(tmpdir)

        expect(repositories).to contain_exactly(root_repo)
      end
    end

    it "can include nested repositories when requested" do
      Dir.mktmpdir do |tmpdir|
        root_repo = File.join(tmpdir, "root")
        nested_repo = File.join(root_repo, "vendor", "nested")

        git(tmpdir, "init", "--initial-branch=main", root_repo)
        git(tmpdir, "init", "--initial-branch=main", nested_repo)

        repositories = described_class.new.recursive_repositories(tmpdir, include_nested: true)

        expect(repositories).to include(root_repo, nested_repo)
      end
    end
  end

  describe GitExplorer::Explorer do
    it "prints custom current output" do
      in_repo("main") do |repo_path|
        output = capture_stdout do
          described_class.start(["current", repo_path, "--format", "$status $currentBranch $mainBranch $sync"])
        end

        expect(output).to eq("✔ main main in-sync\n")
      end
    end

    it "can force color output" do
      in_repo("main") do |repo_path|
        output = capture_stdout do
          described_class.start(["current", repo_path, "--format", "$status $currentBranch $mainBranch $sync", "--color"])
        end

        expect(output).to include("\e[32m")
      end
    end

    it "can fetch before printing sync data" do
      in_repo("main") do |repo_path, remote_path|
        upstream_clone = File.join(File.dirname(repo_path), "upstream-work")
        git(File.dirname(repo_path), "clone", remote_path, upstream_clone)
        configure_git_identity(upstream_clone)
        File.write(File.join(upstream_clone, "upstream.txt"), "remote change\n")
        git(upstream_clone, "add", "upstream.txt")
        git(upstream_clone, "commit", "-m", "Advance main")
        git(upstream_clone, "push", "origin", "main")

        output = capture_stdout do
          described_class.start(["current", repo_path, "--format", "$sync", "--fetch"])
        end

        expect(output).to eq("behind\n")
      end
    end
  end

  def in_repo(default_branch, remote_url: nil)
    Dir.mktmpdir do |tmpdir|
      remote_path = File.join(tmpdir, "remote.git")
      seed_path = File.join(tmpdir, "seed")
      repo_path = File.join(tmpdir, "work")

      git(tmpdir, "init", "--bare", "--initial-branch=#{default_branch}", remote_path)
      git(tmpdir, "clone", remote_path, seed_path)
      configure_git_identity(seed_path)
      File.write(File.join(seed_path, "README.md"), "hello\n")
      git(seed_path, "add", "README.md")
      git(seed_path, "commit", "-m", "Initial commit")
      git(seed_path, "push", "--set-upstream", "origin", default_branch)
      git(tmpdir, "clone", remote_path, repo_path)
      configure_git_identity(repo_path, remote_url: remote_url)

      yield repo_path, remote_path
    end
  end

  def in_local_repo(default_branch)
    Dir.mktmpdir do |tmpdir|
      repo_path = File.join(tmpdir, "repo")
      git(tmpdir, "init", "--initial-branch=#{default_branch}", repo_path)
      configure_git_identity(repo_path)
      File.write(File.join(repo_path, "README.md"), "hello\n")
      git(repo_path, "add", "README.md")
      git(repo_path, "commit", "-m", "Initial commit")

      yield repo_path
    end
  end

  def configure_git_identity(repo_path, remote_url: nil)
    git(repo_path, "config", "user.name", "Test User")
    git(repo_path, "config", "user.email", "test@example.com")
    git(repo_path, "remote", "set-url", "origin", remote_url) if remote_url
  end

  def git(workdir, *args)
    output = `cd #{Shellwords.escape(workdir)} && git #{args.map { |arg| Shellwords.escape(arg) }.join(" ")} 2>&1`
    raise output unless $CHILD_STATUS.success?

    output
  end

  def capture_stdout
    original_stdout = $stdout
    fake_stdout = StringIO.new
    $stdout = fake_stdout
    yield
    fake_stdout.string
  ensure
    $stdout = original_stdout
  end

  def with_env(overrides)
    original = overrides.transform_values { |_,| nil }
    overrides.each_key { |key| original[key] = ENV[key] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
