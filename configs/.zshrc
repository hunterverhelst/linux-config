# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="af-magic"

plugins=(
    git
    docker
    command-not-found
    colorize
    copyfile 
    jump
    safe-paste
    urltools
)

[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
export EDITOR="vim"
export LANG="en_US.UTF-8"

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt APPEND_HISTORY

# ---------------------------------------------------------------------------
# Shell options
# ---------------------------------------------------------------------------
setopt AUTO_CD
setopt CORRECT
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP

# ---------------------------------------------------------------------------
# Source POSIX shell configs
# ---------------------------------------------------------------------------
if [ -d "$HOME/.sh-custom" ]; then
    for file in "$HOME/.sh-custom"/*.sh; do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi
