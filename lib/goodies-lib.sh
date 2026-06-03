#!/bin/bash

# Shared helper library for goodies modules
# Source this from any module install.sh

GOODIES_ROOT="${GOODIES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- Logging ---

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
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
        if ln -s -f "$src" "$dst"; then
            log_info "Linked $dst -> $src"
        else
            log_error "Failed to link $dst -> $src"
            return 1
        fi
    fi
}

ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        if mkdir -p "$dir"; then
            log_info "Created directory $dir"
        else
            log_error "Failed to create directory $dir"
            return 1
        fi
    fi
}

# --- PATH management ---

path_append() {
    local bashrc="$1"
    local entry="$2"
    local line="export PATH=\${PATH}:${entry}"
    if ! grep -qxF "$line" "$bashrc" 2>/dev/null; then
        if echo "$line" >> "$bashrc"; then
            log_info "Added PATH entry: $entry"
        else
            log_error "Failed to append PATH entry to $bashrc"
            return 1
        fi
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
