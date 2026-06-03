#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p ~/.claude/commands

safe_link() {
    local src="$1"
    local dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "WARNING: $dst exists as a regular file, skipping (back it up and re-run to link)"
    else
        ln -s -f "$src" "$dst"
    fi
}

safe_link "${BASEDIR}/settings.json" ~/.claude/settings.json
safe_link "${BASEDIR}/commands/watch-pr.md" ~/.claude/commands/watch-pr.md
