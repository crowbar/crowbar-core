# Check basic commit message formatting
commit_lint.check warn: :all, disable: [:subject_cap]

# Ensure a clean commit history
if git.commits.any? { |c| c.message =~ /^Merge branch/ }
  warn('Please rebase to get rid of the merge commits in this PR')
end
