#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

ensure_dir ~/.claude/commands || exit 1
ensure_dir ~/.bashrc.d || exit 1
ensure_dir ~/.local/bin || exit 1

# Remove legacy command symlinks from before the goodies- prefix rename
for legacy in watch-pr.md distill.md init-conventions.md; do
    [ -L "$HOME/.claude/commands/$legacy" ] && [ ! -e "$HOME/.claude/commands/$legacy" ] && rm "$HOME/.claude/commands/$legacy"
done

safe_link "${BASEDIR}/settings.json" ~/.claude/settings.json
safe_link "${BASEDIR}/commands/goodies-watch.md" ~/.claude/commands/goodies-watch.md
safe_link "${BASEDIR}/commands/goodies-distill.md" ~/.claude/commands/goodies-distill.md
safe_link "${BASEDIR}/commands/goodies-bkm.md" ~/.claude/commands/goodies-bkm.md
safe_link "${BASEDIR}/commands/goodies-review.md" ~/.claude/commands/goodies-review.md
safe_link "${BASEDIR}/snippets" ~/.claude/snippets
safe_link "${BASEDIR}/env.sh" ~/.bashrc.d/claude.sh
safe_link "${BASEDIR}/claude-refresh-token" ~/.local/bin/claude-refresh-token
true
