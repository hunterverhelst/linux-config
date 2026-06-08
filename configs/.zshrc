# ---------------------------------------------------------------------------
# Oh My Zsh defaults (per-device files in ~/.zsh-local/pre can override)
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

export ZSH_COLORIZE_TOOL=pygmentize

# ---------------------------------------------------------------------------
# Pre-OMZ local hooks (per-device, not tracked in repo).
# Runs after repo defaults but before oh-my-zsh loads, so files here can
# override ZSH_THEME, append to plugins=(...), etc. The (N) glob qualifier
# suppresses zsh's "no matches" error on empty directories.
# ---------------------------------------------------------------------------
if [ -d "$HOME/.zsh-local/pre" ]; then
    for file in "$HOME/.zsh-local/pre"/*.sh(N) "$HOME/.zsh-local/pre"/*.zsh(N); do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
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
    for file in "$HOME/.sh-custom"/*.sh(N); do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

# ---------------------------------------------------------------------------
# Source local (per-device) configs - not tracked in repo
# ---------------------------------------------------------------------------
if [ -d "$HOME/.sh-local" ]; then
    for file in "$HOME/.sh-local"/*.sh(N); do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

if [ -d "$HOME/.bash-local" ]; then
    for file in "$HOME/.bash-local"/*.sh(N); do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

if [ -d "$HOME/.zsh-local" ]; then
    for file in "$HOME/.zsh-local"/*.sh(N) "$HOME/.zsh-local"/*.zsh(N); do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi
