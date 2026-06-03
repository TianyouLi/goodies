#!/bin/bash

# Shared helper library for goodies modules
# Source this from any module install.sh

GOODIES_ROOT="${GOODIES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- Logging ---

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# --- Platform detection ---

is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

# --- File operations ---

safe_link() {
    local src="$1"
    local dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        log_warn "$dst exists as a regular file, skipping (back it up and re-run to link)"
        return 1
    else
        ln -s -f "$src" "$dst"
        log_info "Linked $dst -> $src"
    fi
}

ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory $dir"
    fi
}

# --- PATH management ---

path_append() {
    local bashrc="$1"
    local entry="$2"
    local line="export PATH=\${PATH}:${entry}"
    if ! grep -qxF "$line" "$bashrc" 2>/dev/null; then
        echo "$line" >> "$bashrc"
        log_info "Added PATH entry: $entry"
    fi
}

# --- Dependency checks ---

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}
