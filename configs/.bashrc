# ---------------------------------------------------------------------------
# If not running interactively, don't do anything
# ---------------------------------------------------------------------------
case $- in
    *i*) ;;
      *) return;;
esac

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
export EDITOR="vim"
export LANG="en_US.UTF-8"

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ---------------------------------------------------------------------------
# Shell options
# ---------------------------------------------------------------------------
shopt -s checkwinsize
shopt -s autocd
shopt -s cdspell
shopt -s dirspell
shopt -s globstar
shopt -s nocaseglob

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
if [ -x /usr/bin/tput ] && tput setaf 1 >/dev/null 2>&1; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='\u@\h:\w\$ '
fi

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)" 2>/dev/null
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# ---------------------------------------------------------------------------
# Source bash-specific configs
# ---------------------------------------------------------------------------
if [ -d "$HOME/.bash-custom" ]; then
    for file in "$HOME/.bash-custom"/*.sh; do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

# ---------------------------------------------------------------------------
# Source POSIX shell configs
# ---------------------------------------------------------------------------
if [ -d "$HOME/.sh-custom" ]; then
    for file in "$HOME/.sh-custom"/*.sh; do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

# ---------------------------------------------------------------------------
# Source local (per-device) configs - not tracked in repo
# ---------------------------------------------------------------------------
if [ -d "$HOME/.sh-local" ]; then
    for file in "$HOME/.sh-local"/*.sh; do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi

if [ -d "$HOME/.bash-local" ]; then
    for file in "$HOME/.bash-local"/*.sh; do
        [ -f "$file" ] && . "$file"
    done
    unset file
fi
