# Custom git subcommands
git_tree() {
  command git log --graph --oneline --all
}

git_delete-merged() {
  command git branch --merged | grep -v "^\*\\|main|master|dev" | xargs -n 1 git branch -d
}

# git commit with message. Allows committing without needing quotes. Should not be run if any other commit args are needed.
# Example: git cm this is a message with spaces
git_cm() {
  command git commit -m "$*"
}

# Wrapper to handle git subcommands
git() {
  local cmd=$1; shift
  if command -v "git_$cmd" >/dev/null 2>/dev/null; then
    "git_$cmd" "$@"
  else
    command git "$cmd" "$@"
  fi
}

