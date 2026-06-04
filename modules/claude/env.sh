#!/bin/bash
# Claude Code environment — sourced via ~/.bashrc.d/

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
