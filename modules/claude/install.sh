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

# Symlink ALL goodies-* command specs by glob, not a hand-maintained list — so a
# new command (and its built-in --feedback availability) is installed
# automatically the moment its file exists, with nothing to remember here.
for cmd in "${BASEDIR}"/commands/goodies-*.md; do
    [ -e "$cmd" ] || continue
    safe_link "$cmd" ~/.claude/commands/"$(basename "$cmd")"
done

safe_link "${BASEDIR}/snippets" ~/.claude/snippets
safe_link "${BASEDIR}/env.sh" ~/.bashrc.d/claude.sh
safe_link "${BASEDIR}/claude-refresh-token" ~/.local/bin/claude-refresh-token

# Install the always-loaded goodies-feedback trigger into the user-global
# CLAUDE.md. Keyed off the goodies-* namespace (not a command list) so every
# goodies command — including ones added later — can report feedback via
# /goodies-feedback without per-command wiring. Idempotent: the marked block is
# replaced in place on re-install, never duplicated. CLAUDE.md may be co-owned
# by the user, so we edit it in place rather than symlinking.
install_feedback_trigger() {
    local claude_md=~/.claude/CLAUDE.md
    local begin="<!-- BEGIN goodies-feedback (managed by goodies; do not edit inside) -->"
    local block
    block="$(cat <<'EOF'
<!-- BEGIN goodies-feedback (managed by goodies; do not edit inside) -->
## goodies feedback

For ANY `goodies-*` command: if the user passes `--feedback [note]`, OR — while
or just after a `goodies-*` command runs — expresses dissatisfaction with that
command's behavior (e.g. "watch pr doesn't work"), invoke `/goodies-feedback`
with the target command's name and the user's words. `/goodies-feedback` gathers
context, de-duplicates against existing issues (voting + commenting on a match
instead of filing a duplicate), and always confirms before posting. This applies
to goodies commands added in the future too — it is keyed off the `goodies-*`
namespace, not a fixed list.
<!-- END goodies-feedback -->
EOF
)"
    local end="<!-- END goodies-feedback -->"
    touch "$claude_md" || { log_error "cannot write $claude_md; goodies-feedback trigger not installed"; return 1; }
    if grep -qF "$begin" "$claude_md" 2>/dev/null; then
        # Idempotent re-install: replace the existing managed block in place.
        # Use awk (universally present, unlike python3) so this works on minimal
        # systems: copy lines verbatim, but at the BEGIN line emit the fresh
        # block and skip through END. Match the markers ANYWHERE on the line
        # (index > 0, not == 1) so a marker indented by a user or formatter is
        # still refreshed. If a BEGIN has no matching END (malformed block), awk
        # would otherwise drop everything to EOF and truncate the user's file —
        # and since the fresh block carries both markers, the grep check would
        # still pass. Guard that with an END{} that exits non-zero when still
        # skipping, so the temp is discarded and the original is left intact.
        # Write to a temp file and only move it into place if awk succeeded AND
        # the result still contains both markers.
        local tmp
        tmp="$(mktemp "${claude_md}.goodies.XXXXXX")" || { log_error "mktemp failed; goodies-feedback trigger not updated"; return 1; }
        if awk -v blk="$block" -v b="$begin" -v e="$end" '
            index($0, b) > 0 { print blk; skip = 1; next }
            skip && index($0, e) > 0 { skip = 0; next }
            skip { next }
            { print }
            END { if (skip) exit 1 }   # BEGIN without END: bail, do not truncate
        ' "$claude_md" > "$tmp" \
           && grep -qF "$begin" "$tmp" && grep -qF "$end" "$tmp"; then
            if mv "$tmp" "$claude_md"; then
                log_info "refreshed goodies-feedback trigger in $claude_md"
            else
                rm -f "$tmp"
                log_error "failed to move refreshed goodies-feedback block into $claude_md"
                return 1
            fi
        else
            rm -f "$tmp"
            log_error "failed to refresh goodies-feedback trigger in $claude_md (existing block left unchanged)"
            return 1
        fi
    else
        # First install: append the block (leading blank line if file non-empty).
        [ -s "$claude_md" ] && printf '\n' >> "$claude_md"
        printf '%s\n' "$block" >> "$claude_md"
        if grep -qF "$begin" "$claude_md" && grep -qF "$end" "$claude_md"; then
            log_info "installed goodies-feedback trigger into $claude_md"
        else
            log_error "failed to install goodies-feedback trigger into $claude_md"
            return 1
        fi
    fi
}
install_feedback_trigger

true
