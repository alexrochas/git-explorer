require 'spec_helper'

describe GitExplorer do
  include GitExplorer
  it 'has a version number' do
    expect(GitExplorer::VERSION).not_to be nil
  end

  describe '#explore' do
    context 'when exploring directories' do
      let(:up_to_date_message) {
        "gitexplorer
         On branch master
         Your branch is up-to-date with 'origin/master'.
         nothing to commit, working directory clean"
      }
      let(:not_staged_message) {
        "gitexplorer
         On branch master
         Changes not staged for commit:
         (use \"git add <file>...\" to update what will be committed)
         (use \"git checkout -- <file>...\" to discard changes in working directory)

         modified:   ../bin/explore
         modified:   gitexplorer.rb
         modified:   ../spec/gitexplorer_spec.rb

         no changes added to commit (use \"git add\" and/or \"git commit -a\")"
      }
      let(:to_be_commited) {
        "gitexplorer
        On branch master
        Your branch is up-to-date with 'origin/master'.
        Changes to be committed:
          (use 'git reset HEAD <file>...' to unstage)

                modified:   spec/gitexplorer_spec.rb
        "
      }
      let(:to_be_commited_and_unstaged) {
        "gitexplorer
        On branch master
        Your branch is up-to-date with 'origin/master'.
        Changes to be committed:
          (use 'git reset HEAD <file>...' to unstage)

                modified:   spec/gitexplorer_spec.rb

        Changes not staged for commit:
          (use 'git add <file>...'' to update what will be committed)
          (use 'git checkout -- <file>...' to discard changes in working directory)

                modified:   lib/git_explorer.rb
        "
      }
      it { expect(to_be_commited_and_unstaged >> extract_status).to eq(GitExplorer::GitStatus.new([:up_to_date, :not_staged, :to_be_committed], 'gitexplorer', 'master', ['spec/gitexplorer_spec.rb', 'lib/git_explorer.rb']))}
      it { expect(to_be_commited >> extract_status).to eq(GitExplorer::GitStatus.new([:up_to_date, :to_be_committed], 'gitexplorer', 'master', ['spec/gitexplorer_spec.rb']))}
      it { expect(up_to_date_message >> extract_status).to eq(GitExplorer::GitStatus.new([:up_to_date], 'gitexplorer', 'master', [])) }
      it { expect(not_staged_message >> extract_status).to eq(GitExplorer::GitStatus.new([:not_staged], 'gitexplorer', 'master', ['../bin/explore', 'gitexplorer.rb', '../spec/gitexplorer_spec.rb'])) }
    end

    it { expect(extract_dir_name.('./static_response_server/.git')).to eq('./static_response_server/')}
    it { expect(extract_dir_name.('./alexrochas.github.io/.git')).to eq('./alexrochas.github.io/')}
  end
end
