#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "orchestrator installs all modules without error" {
    run bash "$GOODIES_ROOT/install.new.sh"
    assert_success
    [ -L "$HOME/.bash_aliases" ]
    [ -L "$HOME/.claude/settings.json" ]
}

@test "orchestrator is idempotent" {
    bash "$GOODIES_ROOT/install.new.sh"
    run bash "$GOODIES_ROOT/install.new.sh"
    assert_success
}

@test "orchestrator installs specific module" {
    run bash "$GOODIES_ROOT/install.new.sh" git
    assert_success
    [ -L "$HOME/.git_env/git-completion.bash" ]
}

@test "orchestrator fails on unknown module" {
    run bash "$GOODIES_ROOT/install.new.sh" nonexistent
    assert_failure
}
