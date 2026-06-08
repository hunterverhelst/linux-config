#!/bin/sh

set -e

REPO_URL="https://github.com/hunterverhelst/linux-config"
RAW_URL="https://raw.githubusercontent.com/hunterverhelst/linux-config/main"
CLONE_DIR="$HOME/.linux-config"

LOCAL_MODE=false
CAN_INSTALL=false
DO_INSTALL=false
FORCE_INSTALL=false
USE_SUDO=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        -local)   LOCAL_MODE=true ;;
        -install) FORCE_INSTALL=true ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Install a package via apt, using sudo only when not root.
pkg_install() {
    $USE_SUDO apt-get install -y "$@"
}

# Fetch a single file from the repo via wget or curl.
fetch_file() {
    _url="$1"
    _dest="$2"
    if has_cmd wget; then
        wget -q -O "$_dest" "$_url"
    elif has_cmd curl; then
        curl -fsSL -o "$_dest" "$_url"
    else
        printf 'Error: neither wget nor curl is available. Cannot fetch files.\n' >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Ask user about installing packages
#   -install forces installs (useful for non-interactive runs).
#   Otherwise prompt via /dev/tty so this works under `curl ... | sh`,
#   where stdin is the script body rather than the terminal.
# ---------------------------------------------------------------------------
if [ "$FORCE_INSTALL" = true ]; then
    DO_INSTALL=true
elif [ -e /dev/tty ]; then
    printf 'Would you like to install packages? [Y/n] '
    read -r answer </dev/tty
    case "$answer" in
        [nN]|[nN][oO]) DO_INSTALL=false ;;
        *)              DO_INSTALL=true  ;;
    esac
else
    DO_INSTALL=false
fi

# ---------------------------------------------------------------------------
# Determine install capability (only if the user wants to install)
# ---------------------------------------------------------------------------
if [ "$DO_INSTALL" = true ]; then
    if [ "$(id -u)" -eq 0 ]; then
        CAN_INSTALL=true
        USE_SUDO=""
    elif has_cmd sudo && sudo -v 2>/dev/null; then
        # sudo -v prompts for a password if needed and caches the
        # credentials, so later non-interactive sudo calls succeed.
        CAN_INSTALL=true
        USE_SUDO="sudo"
    else
        CAN_INSTALL=false
    fi

    if [ "$CAN_INSTALL" != true ]; then
        printf 'Cannot install packages: need root or sudo access. Skipping installs.\n' >&2
        DO_INSTALL=false
    fi
fi

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------
if [ "$DO_INSTALL" = true ]; then
    $USE_SUDO apt-get update -y

    # If git is not installed, install it first so we can clone the repo.
    if ! has_cmd git; then
        pkg_install git
    fi

    # Install stow first so it can be used for config setup
    if ! has_cmd stow; then
	pkg_install stow
    fi
fi

# ---------------------------------------------------------------------------
# Obtain repository files
# ---------------------------------------------------------------------------
if [ "$LOCAL_MODE" = true ]; then
    # Running from inside the cloned repo.
    REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    if has_cmd git; then
        if [ -d "$CLONE_DIR" ]; then
            git -C "$CLONE_DIR" pull -q
        else
            git clone -q "$REPO_URL" "$CLONE_DIR"
        fi
        REPO_DIR="$CLONE_DIR"
    else
        # Fallback: fetch individual files with wget/curl.
        REPO_DIR="$CLONE_DIR"
        mkdir -p "$REPO_DIR"
        USE_FETCH=true
    fi
fi

# ---------------------------------------------------------------------------
# Install packages from packages.lst (if requested)
# ---------------------------------------------------------------------------
if [ "$DO_INSTALL" = true ]; then
    if [ "${USE_FETCH:-false}" = true ]; then
        fetch_file "$RAW_URL/packages.lst" "$REPO_DIR/packages.lst"
        fetch_file "$RAW_URL/pipx-packages.lst" "$REPO_DIR/pipx-packages.lst"
    fi

    # Read package list, skip blank lines.
    pkgs=""
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        case "$pkg" in
            "") continue ;;
        esac
        pkgs="$pkgs $pkg"
    done < "$REPO_DIR/packages.lst"

    if [ -n "$pkgs" ]; then
        # shellcheck disable=SC2086
        pkg_install $pkgs
    fi
    pkgs=""
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        case "$pkg" in
            "") continue ;;
        esac
        pkgs="$pkgs $pkg"
    done < "$REPO_DIR/pipx-packages.lst"
    pipx ensurepath
    if [ -n "$pkgs" ]; then
        # shellcheck disable=SC2086
        pipx install $pkgs
    fi


    # Generate en_US.UTF-8 locale if locales is available.
    if has_cmd locale-gen; then
        $USE_SUDO sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
        $USE_SUDO locale-gen en_US.UTF-8
    fi
fi

# ---------------------------------------------------------------------------
# File list for fetch-mode (paths relative to configs/).
# Update this when you add or remove dotfiles.
# ---------------------------------------------------------------------------
CONFIGS_FILES=""

# ---------------------------------------------------------------------------
# Verify stow is available
# ---------------------------------------------------------------------------
if ! has_cmd stow; then
    printf 'Error: GNU Stow is required but not installed.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Install oh-my-zsh and set zsh as the default shell
# ---------------------------------------------------------------------------
if [ "$DO_INSTALL" = true ] || has_cmd zsh; then
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        printf 'Installing oh-my-zsh...\n'
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    # Remove the installer's .zshrc so stow can link our custom one.
    rm -f "$HOME/.zshrc"

    ZSH_PATH="$(command -v zsh)"
    if [ -n "$ZSH_PATH" ]; then
        CURRENT_SHELL="$(getent passwd "$(id -un)" | cut -d: -f7)"
        if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
            printf 'Setting zsh as the default shell...\n'
            if [ "$(id -u)" -eq 0 ]; then
                chsh -s "$ZSH_PATH"
            else
                chsh -s "$ZSH_PATH" "$(id -un)"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Fetch config files when in fetch mode
# ---------------------------------------------------------------------------
if [ "${USE_FETCH:-false}" = true ]; then
    if [ -z "$CONFIGS_FILES" ]; then
        printf 'Warning: no file list defined for configs in fetch mode. Skipping.\n' >&2
    else
        for _rel in $CONFIGS_FILES; do
            _dir="$(dirname "$_rel")"
            mkdir -p "$REPO_DIR/configs/$_dir"
            fetch_file "$RAW_URL/configs/$_rel" "$REPO_DIR/configs/$_rel"
        done
    fi
fi

# ---------------------------------------------------------------------------
# Stow configs into $HOME
# ---------------------------------------------------------------------------
if [ -d "$REPO_DIR/configs" ]; then
    printf 'Installing config files...\n'
    stow -d "$REPO_DIR" -t "$HOME" --adopt configs

    # --adopt moved any conflicting files into the repo. Restore the repo
    # versions so the symlinks point to the correct content.
    if has_cmd git && [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" checkout -- configs
    fi
else
    printf 'Warning: configs folder not found in repo. Skipping.\n' >&2
fi

# ---------------------------------------------------------------------------
# Scaffold per-device local config directories (not tracked in repo).
#   ~/.sh-local    - sourced by both .bashrc and .zshrc
#   ~/.bash-local  - sourced by .bashrc only
#   ~/.zsh-local   - sourced by .zshrc only
# Each is optional; rc files skip missing directories silently.
# ---------------------------------------------------------------------------
for _dir in "$HOME/.sh-local" "$HOME/.bash-local" "$HOME/.zsh-local" "$HOME/.zsh-local/pre"; do
    if [ ! -d "$_dir" ]; then
        mkdir -p "$_dir"
        printf 'Created %s for per-device shell configs.\n' "$_dir"
    fi
done
unset _dir

printf 'Setup complete.\n'
source ~/.zshrc
