#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "orchestrator installs all modules without error" {
    run bash "$GOODIES_ROOT/install.sh"
    assert_success
    [ -L "$HOME/.bash_aliases" ]
    [ -L "$HOME/.claude/settings.json" ]
}

@test "orchestrator is idempotent" {
    bash "$GOODIES_ROOT/install.sh"
    run bash "$GOODIES_ROOT/install.sh"
    assert_success
}

@test "orchestrator installs specific module" {
    run bash "$GOODIES_ROOT/install.sh" git
    assert_success
    [ -L "$HOME/.git_env/git-completion.bash" ]
}

@test "orchestrator fails on unknown module" {
    run bash "$GOODIES_ROOT/install.sh" nonexistent
    assert_failure
}

@test "orchestrator without --full skips bootstrap" {
    mkdir -p "$GOODIES_ROOT/modules/_test"
    echo '#!/bin/bash' > "$GOODIES_ROOT/modules/_test/install.sh"
    echo 'touch "$HOME/.test_installed"' >> "$GOODIES_ROOT/modules/_test/install.sh"
    echo '#!/bin/bash' > "$GOODIES_ROOT/modules/_test/bootstrap.sh"
    echo 'touch "$HOME/.test_bootstrapped"' >> "$GOODIES_ROOT/modules/_test/bootstrap.sh"
    chmod +x "$GOODIES_ROOT/modules/_test/install.sh" "$GOODIES_ROOT/modules/_test/bootstrap.sh"

    run bash "$GOODIES_ROOT/install.sh" _test
    assert_success
    [ -f "$HOME/.test_installed" ]
    [ ! -f "$HOME/.test_bootstrapped" ]

    rm -rf "$GOODIES_ROOT/modules/_test"
}

@test "orchestrator --full runs bootstrap scripts" {
    mkdir -p "$GOODIES_ROOT/modules/_test"
    echo '#!/bin/bash' > "$GOODIES_ROOT/modules/_test/install.sh"
    echo 'touch "$HOME/.test_installed"' >> "$GOODIES_ROOT/modules/_test/install.sh"
    echo '#!/bin/bash' > "$GOODIES_ROOT/modules/_test/bootstrap.sh"
    echo 'touch "$HOME/.test_bootstrapped"' >> "$GOODIES_ROOT/modules/_test/bootstrap.sh"
    chmod +x "$GOODIES_ROOT/modules/_test/install.sh" "$GOODIES_ROOT/modules/_test/bootstrap.sh"

    run bash "$GOODIES_ROOT/install.sh" --full _test
    assert_success
    [ -f "$HOME/.test_installed" ]
    [ -f "$HOME/.test_bootstrapped" ]

    rm -rf "$GOODIES_ROOT/modules/_test"
}
