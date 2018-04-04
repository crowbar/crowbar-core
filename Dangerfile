# Check basic commit message formatting
commit_lint.check warn: :all, disable: [:subject_cap, :subject_length]

# Check for commit message being less than 70
if git.commits.any? { |c| c.message.partition("\n")[0].length >= 70 }
  warn('Please shorten commit subjects to less than 70 chars')
end

# Ensure a clean commit history
if git.commits.any? { |c| c.message =~ /^Merge branch/ }
  warn('Please rebase to get rid of the merge commits in this PR')
end
