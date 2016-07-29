require 'spec_helper'

describe GitExplorer do
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
      it { expect(up_to_date_message >> GitExplorer::extract_status).to eq(GitExplorer::GitStatus.new(:up_to_date, "gitexplorer", "master", [])) }
      it { expect(not_staged_message >> GitExplorer::extract_status).to eq(GitExplorer::GitStatus.new(:not_staged, "gitexplorer", "master", ["../bin/explore", "gitexplorer.rb", "../spec/gitexplorer_spec.rb"])) }
    end
  end
end
