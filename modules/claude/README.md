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

## Reference

Source: https://github.com/TianyouLi/goodies/tree/master/modules/claude
