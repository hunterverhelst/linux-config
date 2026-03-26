bsource() {
  source "$HOME/.bashrc"
}

mkcd() {
    TARGET_DIR=$1
    mkdir $TARGET_DIR && cd $TARGET_DIR
}

noerror() {
  "$@ 2>/dev/null"
}