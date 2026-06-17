# Claude module — overview

This module ships claude-related tooling that the goodies installer
(`bash install.sh claude`) symlinks into your home directory. Beyond the
core token-refresh setup (the original purpose of this module), it now
hosts a small library of slash commands, snippet conventions, and
browser-side userscripts that work together.

## Layout

```
modules/claude/
├── claude-refresh-token        # token-refresh CLI (installed to ~/.local/bin)
├── env.sh                      # claude shell function (sourced by ~/.bashrc.d)
├── settings.json               # ~/.claude/settings.json
├── commands/                   # slash commands for Claude Code
│   ├── goodies-watch.md        # poll a PR for Copilot reviews; surface findings
│   ├── goodies-distill.md      # scan recent sessions for portable solutions
│   ├── goodies-bkm.md          # append convention snippets to project CLAUDE.md
│   └── goodies-review.md       # human-expert PR collaboration (5-layer review) [PR #37]
├── snippets/                   # convention snippets used by goodies-bkm + goodies-review
│   ├── branch-naming.md
│   ├── conventional-commits.md
│   ├── copilot-review-workflow.md
│   ├── copilot-ruleset.md
│   ├── pr-checklist.md
│   └── pr-description.md
└── scripts/                    # external-tool helpers (browser, etc.)
    └── tampermonkey/           # browser-side userscripts (NOT installed by install.sh)
        └── copilot-request-review.user.js
```

`install.sh` symlinks the filesystem assets — env.sh into
`~/.bashrc.d/`, the claude-refresh-token CLI into `~/.local/bin/`, the
settings.json + commands/ + snippets/ into `~/.claude/`. The
**scripts/tampermonkey/** subdirectory is intentionally excluded: those
files are installed via the Tampermonkey browser extension's UI, not via
filesystem symlinks. See `scripts/tampermonkey/README.md` for the install
flow.

## How the assets relate

This is a small library of cooperating tools, not a single feature.
Knowing which asset depends on (or complements) which is the navigation
aid:

| Asset | Depends on | Complements |
|---|---|---|
| `env.sh` (claude function) | `~/.claude_bedrock_token` (managed by claude-refresh-token) | none |
| `claude-refresh-token` | (standalone) | `env.sh` (writes the file env.sh reads) |
| `commands/goodies-distill.md` | session transcripts under `~/.claude/projects/` | none |
| `commands/goodies-bkm.md` | `snippets/*.md` (the snippet corpus) | none |
| `commands/goodies-review.md` | `snippets/copilot-review-workflow.md`, `snippets/pr-checklist.md` (when grounding) | `scripts/tampermonkey/copilot-request-review.user.js` (removes the manual click for re-review) |
| `commands/goodies-watch.md` | `gh` CLI authenticated | `scripts/tampermonkey/copilot-request-review.user.js` (with the userscript installed, Copilot re-review triggers via the marker handshake instead of relying on GitHub's auto-trigger; see `scripts/tampermonkey/README.md` for the handshake design) |
| `scripts/tampermonkey/copilot-request-review.user.js` | Tampermonkey browser extension | `goodies-watch`, `goodies-review` (both benefit when Copilot review fires reliably on push) |

The userscript is the only asset that lives outside the filesystem-managed
install flow. When in doubt: filesystem assets → `install.sh` symlinks
them; browser assets → install via the extension's UI.

---

# Claude Code Token Refresh Without Re-sourcing

**Problem:** Every time the AWS bearer token expires (~weekly), you have to update `.bashrc` and `source ~/.bashrc` in every open terminal.

**Solution:** Store the token in a file and read it fresh on each `claude` invocation.

## Quick Start (using goodies repo)

```bash
git clone https://github.com/TianyouLi/goodies.git ~/goodies
cd ~/goodies && bash install.sh claude
source ~/.bashrc   # one-time, to load the claude function
claude-refresh-token
```

After this one-time setup, new shells load the function automatically.
Token refreshes take effect immediately in all terminals — no re-sourcing needed.

## Manual Setup

If you don't want the full repo, here's the standalone version:

1. Create `~/.bashrc.d/claude.sh` (or add to your shell rc):

```bash
claude() {
    local token_file="$HOME/.claude_bedrock_token"
    if [ ! -f "$token_file" ] || [ ! -s "$token_file" ]; then
        echo "Error: $token_file not found or empty. Run claude-refresh-token to set your token." >&2
        return 1
    fi
    local token
    token=$(<"$token_file")
    token="${token%$'\n'}"
    AWS_REGION="us-east-2" \
    CLAUDE_CODE_USE_BEDROCK=1 \
    AWS_BEARER_TOKEN_BEDROCK="$token" \
    command claude --dangerously-skip-permissions "$@"
}
```

> **Note:** `--dangerously-skip-permissions` disables Claude Code's interactive permission
> prompts (file edits, shell commands run without asking). Remove this flag if you prefer
> the default safety prompts.

2. Create `claude-refresh-token` somewhere on your PATH and make it executable (`chmod +x`):

```bash
#!/bin/bash
TOKEN_FILE="$HOME/.claude_bedrock_token"

if [ -n "$1" ]; then
    token="$1"
else
    printf "Paste new AWS_BEARER_TOKEN_BEDROCK: "
    read -rs token
    echo
fi

if [ -z "$token" ]; then
    echo "Error: empty token" >&2
    exit 1
fi

(umask 077 && printf '%s' "$token" > "$TOKEN_FILE")
echo "Token saved to $TOKEN_FILE (all new claude invocations will use it)"
```

3. Make sure your `.bashrc` sources `~/.bashrc.d/*`:

```bash
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        [ -f "$rc" ] && . "$rc"
    done
fi
```

## Usage

```bash
# Refresh token interactively (token won't echo to terminal or shell history)
claude-refresh-token

# Or pass directly (note: appears in shell history and process list)
claude-refresh-token "ABSK..."

# All terminals use the new token immediately — no source needed
claude
```

## Why it works

The `claude` shell function reads the token from disk on every invocation. Env vars are scoped to the `command claude` process only — they don't pollute your shell or affect other AWS tools. The token file is created with `600` permissions via `umask 077`.

---

# /goodies-distill — Extract Portable Solutions from Sessions

**Problem:** You solve interesting problems in Claude sessions all the time — workarounds, automation scripts, config patterns — but they stay buried in conversation history and are never shared.

**Solution:** `/goodies-distill` scans your recent session transcripts, identifies reusable solutions, and offers to extract them into standalone tools or documentation.

## Usage

```bash
# In any Claude Code session:
/goodies-distill          # scan since last run (or last 7 days if first time)
/goodies-distill -30      # scan last 30 days
```

## What it does

1. **Scans** all session transcripts (finds `*.jsonl` under `~/.claude/projects/`) within the time range
2. **Identifies** portable candidates:
   - New scripts or tools created
   - Workarounds for non-obvious problems
   - Reusable shell functions or config snippets
   - Multi-step workflows that could be scripted
3. **Presents** a digest grouped by project
4. **Extracts** (with your approval) selected solutions into proper modules with install scripts and PRs

## Example output

```
## Session Digest (last 7 days)

### goodies
Session: Jun 4 — Built token-from-file mechanism for Claude Bedrock auth
Portable candidates:
- claude-refresh-token — eliminates re-sourcing .bashrc across terminals

### linux
Session: Jun 2 — Debugged kernel boot failure with kexec fallback
Portable candidates:
- kexec retry with grub fallback — useful for kernel developers doing rapid iteration
```

## How it remembers

`/goodies-distill` stores a timestamp in `~/.claude/.distill_last_run` after each run. Next time you invoke it without arguments, it only scans sessions since that timestamp — so you won't see the same candidates twice.

## What it skips

- Project-specific bug fixes and feature work (not portable)
- Sessions with no file creation or significant automation
- Sensitive data is excluded from extracted solutions (tokens, internal URLs are never carried over)

## Reference

Source: https://github.com/TianyouLi/goodies/tree/master/modules/claude
