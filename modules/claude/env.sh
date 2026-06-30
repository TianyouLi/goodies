#!/bin/bash
# Claude Code environment — sourced via ~/.bashrc.d/

# Absolute path to goodies scripts dir — resolved at source-time, not install-time
export GOODIES_SCRIPTS
GOODIES_SCRIPTS="$(cd "$(dirname "$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")")/scripts" && pwd)"

if alias claude &>/dev/null; then
    if [[ -t 0 && -t 1 ]]; then
        echo "Warning: 'claude' is already defined as an alias: $(alias claude)" >&2
        read -rp "Override with goodies claude wrapper function? [Y/n] " _reply || _reply=""
        if [[ "$_reply" =~ ^[Nn] ]]; then
            unset _reply
            return 0 2>/dev/null || exit 0
        fi
        unset _reply
    fi
    unalias claude
fi

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
