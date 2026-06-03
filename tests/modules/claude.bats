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

@test "claude module installs watch-pr command symlink" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/commands/watch-pr.md" ]
    [ "$(readlink "$HOME/.claude/commands/watch-pr.md")" = "$GOODIES_ROOT/modules/claude/commands/watch-pr.md" ]
}

@test "claude module creates required directories" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -d "$HOME/.claude/commands" ]
}

@test "claude module install is idempotent" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ -L "$HOME/.claude/commands/watch-pr.md" ]
}

@test "claude module skips existing regular settings.json" {
    mkdir -p "$HOME/.claude"
    echo '{"custom": true}' > "$HOME/.claude/settings.json"
    run bash "$GOODIES_ROOT/modules/claude/install.sh"
    assert_success
    [ ! -L "$HOME/.claude/settings.json" ]
    grep -q '"custom"' "$HOME/.claude/settings.json"
}
