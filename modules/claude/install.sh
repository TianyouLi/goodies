#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

ensure_dir ~/.claude/commands || exit 1

safe_link "${BASEDIR}/settings.json" ~/.claude/settings.json
safe_link "${BASEDIR}/commands/watch-pr.md" ~/.claude/commands/watch-pr.md
true
