

mkcd() {
    TARGET_DIR=$1
    mkdir $TARGET_DIR && cd $TARGET_DIR
}

noerror() {
  "$@ 2>/dev/null"
}

# Pick editor based on whether this is an SSH session.
# Aliasing vim->nvim only happens locally so the alias doesn't leak into
# remote shells where nvim may not be installed.
if [ -n "$SSH_CONNECTION" ]; then
    export EDITOR='vim'
else
    export EDITOR='nvim'
    alias vim='nvim'
fi