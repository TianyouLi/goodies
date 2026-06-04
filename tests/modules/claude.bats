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
