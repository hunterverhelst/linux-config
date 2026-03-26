# Custom docker subcommands

# Docker quick run
docker_qr() {
  command docker run -it --rm "$@"
}

# Wrapper to handle docker subcommands
docker() {
  local cmd=$1; shift
  if command -v "docker_$cmd" >/dev/null 2>/dev/null; then
    "docker_$cmd" "$@"
  else
    command docker "$cmd" "$@"
  fi
}
