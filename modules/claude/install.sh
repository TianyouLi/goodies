#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

ensure_dir ~/.claude/commands || exit 1
ensure_dir ~/.bashrc.d || exit 1
ensure_dir ~/.local/bin || exit 1

safe_link "${BASEDIR}/settings.json" ~/.claude/settings.json
safe_link "${BASEDIR}/commands/watch-pr.md" ~/.claude/commands/watch-pr.md
safe_link "${BASEDIR}/env.sh" ~/.bashrc.d/claude.sh
safe_link "${BASEDIR}/claude-refresh-token" ~/.local/bin/claude-refresh-token
true
