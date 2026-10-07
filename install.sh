#!/usr/bin/env bash
#
# install.sh - Deploy linux-conf dotfiles and set up the shell environment.
#
# What it does:
#   1. Places config files into their proper locations (symlink by default,
#      copy with --copy).
#   2. Installs starship (if missing) via the official installer.
#   3. Installs neovim (if missing) from the official release tarball into
#      /opt (may prompt for sudo), per the neovim install docs.
#   4. Injects a managed block into a shell rc file that:
#        - initializes starship
#        - adds the neovim bin dir to PATH (per neovim docs)
#        - sources the auto-attach tmux snippet (~/.bashrc.tmux)
#      By default the target is ~/.bashrc, but it can be any file (useful on
#      machines where ~/.bashrc is not writable but sources another file you
#      control). See --bashrc / LINUX_CONF_BASHRC.
#
# Usage:
#   ./install.sh            # symlink dotfiles into place
#   ./install.sh --copy     # copy files instead of symlinking
#   ./install.sh --no-starship   # skip installing starship
#   ./install.sh --no-neovim     # skip installing neovim
#   ./install.sh --bashrc PATH   # write the managed block to PATH instead of ~/.bashrc
#   ./install.sh --dry-run  # show what would happen without changing anything
#
# The target rc file can also be set via the LINUX_CONF_BASHRC env var.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.linux-conf-backup/$(date +%Y%m%d-%H%M%S)"

MODE="symlink"      # symlink | copy
INSTALL_STARSHIP=1
INSTALL_NEOVIM=1
DRY_RUN=0

# Target rc file for the managed block. Precedence: --bashrc > env > default.
TARGET_BASHRC="${LINUX_CONF_BASHRC:-$HOME/.bashrc}"

BLOCK_BEGIN="# >>> linux-conf managed block >>>"
BLOCK_END="# <<< linux-conf managed block <<<"

# Neovim release naming follows `nvim-linux-<arch>` (x86_64 / arm64).
case "$(uname -m)" in
    x86_64|amd64)   NVIM_ARCH="x86_64" ;;
    aarch64|arm64)  NVIM_ARCH="arm64" ;;
    *)              NVIM_ARCH="" ;;   # unknown; neovim install will be skipped
esac
NVIM_NAME="nvim-linux-${NVIM_ARCH}"
NVIM_DIR="/opt/${NVIM_NAME}"
NVIM_BIN="${NVIM_DIR}/bin"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

run() {
    # Execute a command, or just print it in dry-run mode.
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

usage() {
    sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --copy)         MODE="copy" ;;
        --no-starship)  INSTALL_STARSHIP=0 ;;
        --no-neovim)    INSTALL_NEOVIM=0 ;;
        --dry-run)      DRY_RUN=1 ;;
        --bashrc)
            [ $# -ge 2 ] || { err "--bashrc requires a path argument"; usage 1; }
            TARGET_BASHRC="$2"; shift ;;
        --bashrc=*)     TARGET_BASHRC="${1#*=}" ;;
        -h|--help)      usage 0 ;;
        *) err "Unknown option: $1"; usage 1 ;;
    esac
    shift
done

# Expand a leading ~ in the target path (in case it was passed quoted).
case "$TARGET_BASHRC" in
    "~/"*) TARGET_BASHRC="$HOME/${TARGET_BASHRC#\~/}" ;;
    "~")   TARGET_BASHRC="$HOME" ;;
esac

# ---------------------------------------------------------------------------
# File placement
#
# Map of "source (relative to repo)" -> "destination (absolute)".
# Add new dotfiles here and they'll be deployed automatically.
# ---------------------------------------------------------------------------
declare -A FILES=(
    [".bashrc.tmux"]="$HOME/.bashrc.tmux"
    [".tmux.conf"]="$HOME/.tmux.conf"
    [".config/starship.toml"]="$HOME/.config/starship.toml"
)

# Directories deployed as a whole (source relative to repo -> destination).
declare -A DIRS=(
    [".config/nvim"]="$HOME/.config/nvim"
    ["bin"]="$HOME/bin"
)

backup() {
    # Back up an existing path (file, dir, or symlink) before replacing it.
    local target="$1"
    if [ -e "$target" ] || [ -L "$target" ]; then
        local rel="${target#"$HOME"/}"
        local dest="$BACKUP_DIR/$rel"
        run mkdir -p "$(dirname "$dest")"
        log "Backing up $target -> $dest"
        run mv "$target" "$dest"
    fi
}

place() {
    # place SOURCE DEST — deploy a single path (file or directory).
    local src="$1" dest="$2"

    if [ ! -e "$src" ]; then
        warn "Source missing, skipping: $src"
        return
    fi

    # If a correct symlink is already in place, do nothing.
    if [ "$MODE" = "symlink" ] && [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
        log "Already linked: $dest"
        return
    fi

    backup "$dest"
    run mkdir -p "$(dirname "$dest")"

    if [ "$MODE" = "symlink" ]; then
        log "Linking $dest -> $src"
        run ln -s "$src" "$dest"
    else
        log "Copying $src -> $dest"
        if [ -d "$src" ]; then
            run cp -R "$src" "$dest"
        else
            run cp "$src" "$dest"
        fi
    fi
}

deploy_files() {
    log "Deploying config files (mode: $MODE)"
    local src dest
    for src in "${!FILES[@]}"; do
        place "$REPO_DIR/$src" "${FILES[$src]}"
    done
    for src in "${!DIRS[@]}"; do
        place "$REPO_DIR/$src" "${DIRS[$src]}"
    done
}

# ---------------------------------------------------------------------------
# Starship installation
# ---------------------------------------------------------------------------
install_starship() {
    if [ "$INSTALL_STARSHIP" -eq 0 ]; then
        log "Skipping starship installation (--no-starship)"
        return
    fi
    if command -v starship >/dev/null 2>&1; then
        log "starship already installed: $(command -v starship)"
        return
    fi

    log "Installing starship..."
    if command -v curl >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '   [dry-run] curl -sS https://starship.rs/install.sh | sh -s -- --yes\n'
        else
            # Uses the official installer's default bin dir (/usr/local/bin,
            # may prompt for sudo). Override by installing starship yourself
            # and re-running, or use --no-starship.
            curl -sS https://starship.rs/install.sh | sh -s -- --yes
        fi
    else
        err "curl not found; install starship manually: https://starship.rs/"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Neovim installation (official release tarball into /opt)
# https://github.com/neovim/neovim/blob/master/INSTALL.md
# ---------------------------------------------------------------------------
install_neovim() {
    if [ "$INSTALL_NEOVIM" -eq 0 ]; then
        log "Skipping neovim installation (--no-neovim)"
        return
    fi
    if [ -z "$NVIM_ARCH" ]; then
        warn "Unsupported arch '$(uname -m)' for neovim release tarball; skipping. Install manually."
        return
    fi
    if command -v nvim >/dev/null 2>&1; then
        log "neovim already installed: $(command -v nvim)"
        return
    fi
    if [ -x "$NVIM_BIN/nvim" ]; then
        log "neovim already present at $NVIM_BIN/nvim"
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        err "curl not found; install neovim manually: https://github.com/neovim/neovim/blob/master/INSTALL.md"
        return 1
    fi

    local url="https://github.com/neovim/neovim/releases/latest/download/${NVIM_NAME}.tar.gz"
    local tarball="/tmp/${NVIM_NAME}.tar.gz"

    # sudo only if we aren't already root and /opt isn't user-writable.
    local SUDO=""
    if [ "$(id -u)" -ne 0 ] && [ ! -w /opt ]; then
        SUDO="sudo"
    fi

    log "Installing neovim ($NVIM_NAME) into /opt..."
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   [dry-run] curl -Lo %s %s\n' "$tarball" "$url"
        printf '   [dry-run] %s rm -rf %s\n' "$SUDO" "$NVIM_DIR"
        printf '   [dry-run] %s tar -C /opt -xzf %s\n' "$SUDO" "$tarball"
        return
    fi

    curl -L --fail -o "$tarball" "$url"
    $SUDO rm -rf "$NVIM_DIR"
    $SUDO tar -C /opt -xzf "$tarball"
    rm -f "$tarball"
    log "neovim installed: $NVIM_BIN/nvim"
}

# ---------------------------------------------------------------------------
# .bashrc managed block
# ---------------------------------------------------------------------------
build_block() {
    # Emit the managed block contents.
    cat <<EOF
# >>> linux-conf managed block >>>
# Managed by linux-conf/install.sh — edits inside this block may be overwritten.

# starship prompt
if command -v starship >/dev/null 2>&1; then
    eval "\$(starship init bash)"
fi

# neovim (installed under /opt per neovim docs)
if [ -d "$NVIM_BIN" ]; then
    case ":\$PATH:" in
        *":$NVIM_BIN:"*) ;;
        *) export PATH="\$PATH:$NVIM_BIN" ;;
    esac
fi

# --- Auto-attach or create tmux ---
# Portable snippet lives in ~/.bashrc.tmux; source it if present.
[ -f ~/.bashrc.tmux ] && . ~/.bashrc.tmux
# <<< linux-conf managed block <<<
EOF
}

update_bashrc() {
    local bashrc="$TARGET_BASHRC"
    log "Updating managed block in $bashrc"

    # Ensure the target is writable (or creatable). Fail early with a clear msg.
    if [ -e "$bashrc" ]; then
        if [ ! -w "$bashrc" ]; then
            err "Target file is not writable: $bashrc"
            err "Point --bashrc at a file you can edit (e.g. the file your legacy bashrc sources)."
            return 1
        fi
    else
        local dir
        dir="$(dirname "$bashrc")"
        if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then
            err "Cannot create target file (directory missing or not writable): $bashrc"
            return 1
        fi
        log "Target does not exist yet; it will be created: $bashrc"
    fi

    run touch "$bashrc"

    local tmp
    tmp="$(mktemp)"
    # Strip any existing managed block, then append the fresh one.
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        $0 == b {skip=1; next}
        $0 == e {skip=0; next}
        !skip {print}
    ' "$bashrc" > "$tmp"

    # Remove the old standalone `eval "$(starship init bash)"` line if present,
    # since the managed block now owns starship init.
    grep -v '^eval "\$(starship init bash)"$' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"

    build_block >> "$tmp"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   [dry-run] would write updated %s:\n' "$bashrc"
        printf '   ----------------------------------------\n'
        sed 's/^/   | /' "$tmp"
        printf '   ----------------------------------------\n'
        rm -f "$tmp"
    else
        # Back up the original once per run.
        backup_bashrc "$bashrc"
        # Preserve the target's permissions by writing in place.
        cat "$tmp" > "$bashrc"
        rm -f "$tmp"
    fi
}

backup_bashrc() {
    local bashrc="$1"
    # Use the basename plus a flattened path hint so distinct targets don't
    # collide in the backup dir.
    local dest="$BACKUP_DIR/rcfile$(printf '%s' "$bashrc" | tr '/' '_')"
    mkdir -p "$BACKUP_DIR"
    cp "$bashrc" "$dest"
    log "Backed up $bashrc -> $dest"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "linux-conf installer"
    log "Repo:    $REPO_DIR"
    log "Backups: $BACKUP_DIR"
    log "RC file: $TARGET_BASHRC"
    [ "$DRY_RUN" -eq 1 ] && warn "DRY RUN — no changes will be made"

    deploy_files
    install_starship
    install_neovim
    update_bashrc

    log "Done. Open a new shell or run: source ~/.bashrc"
}

main "$@"
