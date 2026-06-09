#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "claude module installs settings.json symlink" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ "$(readlink "$HOME/.claude/settings.json")" = "$GOODIES_ROOT/modules/claude/settings.json" ]
}

@test "claude module installs command symlinks" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/commands/goodies-watch.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-watch.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-watch.md" ]
    [ -L "$HOME/.claude/commands/goodies-distill.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-distill.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-distill.md" ]
    [ -L "$HOME/.claude/commands/goodies-bkm.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-bkm.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-bkm.md" ]
}

@test "claude module installs snippets symlink" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/snippets" ]
    [ "$(readlink "$HOME/.claude/snippets")" = "$GOODIES_ROOT/modules/claude/snippets" ]
}

@test "claude module removes broken legacy symlinks" {
    mkdir -p "$HOME/.claude/commands"
    ln -s "/nonexistent/watch-pr.md" "$HOME/.claude/commands/watch-pr.md"
    ln -s "/nonexistent/distill.md" "$HOME/.claude/commands/distill.md"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ ! -e "$HOME/.claude/commands/watch-pr.md" ]
    [ ! -e "$HOME/.claude/commands/distill.md" ]
}

@test "claude module creates required directories" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -d "$HOME/.claude/commands" ]
}

@test "claude module install is idempotent" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ -L "$HOME/.claude/commands/goodies-watch.md" ]
    [ -L "$HOME/.claude/commands/goodies-distill.md" ]
    [ -L "$HOME/.claude/commands/goodies-bkm.md" ]
}

@test "claude module skips existing regular settings.json" {
    mkdir -p "$HOME/.claude"
    echo '{"custom": true}' > "$HOME/.claude/settings.json"
    run bash "$GOODIES_ROOT/modules/claude/install.sh"
    assert_success
    [ ! -L "$HOME/.claude/settings.json" ]
    grep -q '"custom"' "$HOME/.claude/settings.json"
}

@test "claude module installs env.sh symlink to bashrc.d" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.bashrc.d/claude.sh" ]
    [ "$(readlink "$HOME/.bashrc.d/claude.sh")" = "$GOODIES_ROOT/modules/claude/env.sh" ]
}

# --- env.sh tests ---

@test "env.sh defines claude function when no alias exists" {
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && type -t claude'
    assert_success
    assert_output "function"
}

@test "env.sh claude function fails when token file missing" {
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && claude --version 2>&1'
    assert_failure
    assert_output --partial "not found or empty"
}

@test "env.sh claude function fails when token file is empty" {
    touch "$HOME/.claude_bedrock_token"
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && claude --version 2>&1'
    assert_failure
    assert_output --partial "not found or empty"
}

@test "env.sh claude function sets environment variables correctly" {
    echo "test-token-123" > "$HOME/.claude_bedrock_token"
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'FAKE'
#!/bin/bash
echo "REGION=$AWS_REGION"
echo "BEDROCK=$CLAUDE_CODE_USE_BEDROCK"
echo "TOKEN=$AWS_BEARER_TOKEN_BEDROCK"
FAKE
    chmod +x "$HOME/bin/claude"
    run bash -c '
        export PATH="$HOME/bin:$PATH"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        claude
    '
    assert_success
    assert_line "REGION=us-east-2"
    assert_line "BEDROCK=1"
    assert_line "TOKEN=test-token-123"
}

@test "env.sh strips trailing newline from token" {
    printf "my-token\n" > "$HOME/.claude_bedrock_token"
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'FAKE'
#!/bin/bash
printf "TOKEN=%s\n" "$AWS_BEARER_TOKEN_BEDROCK"
FAKE
    chmod +x "$HOME/bin/claude"
    run bash -c '
        export PATH="$HOME/bin:$PATH"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        claude
    '
    assert_success
    assert_output "TOKEN=my-token"
}

@test "env.sh overrides alias silently in non-interactive shell" {
    run bash -c '
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        type -t claude
    '
    assert_success
    assert_output "function"
}

@test "env.sh removes alias when overriding" {
    run bash -c '
        shopt -s expand_aliases
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        alias claude 2>&1
    '
    assert_failure
}

@test "env.sh does not prompt in non-interactive shell (no TTY)" {
    run bash -c '
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh" 2>&1
    '
    assert_success
    refute_output --partial "Override with goodies"
}

@test "env.sh interactive prompt defaults to override on empty input" {
    run bash -c '
        echo "" | bash -c '\''
            shopt -s expand_aliases
            alias claude="echo old"
            source <(sed "s/\[\[ -t 0 && -t 1 \]\]/true/" "$GOODIES_ROOT/modules/claude/env.sh") 2>/dev/null
            type -t claude
        '\''
    '
    assert_success
    assert_output "function"
}

@test "env.sh interactive prompt skips function on N input" {
    run bash -c '
        echo "n" | bash -c '\''
            shopt -s expand_aliases
            alias claude="echo old"
            source <(sed "s/\[\[ -t 0 && -t 1 \]\]/true/" "$GOODIES_ROOT/modules/claude/env.sh") 2>/dev/null
            type -t claude 2>/dev/null || echo "not-defined"
        '\''
    '
    assert_success
    assert_output "alias"
}
