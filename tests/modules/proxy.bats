#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "proxy module adds PATH entry to .bashrc" {
    bash "$GOODIES_ROOT/modules/proxy/install.sh"
    grep -q "modules/proxy" "$HOME/.bashrc"
}

@test "proxy module PATH entry is idempotent" {
    bash "$GOODIES_ROOT/modules/proxy/install.sh"
    bash "$GOODIES_ROOT/modules/proxy/install.sh"
    local count
    count=$(grep -c "modules/proxy" "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}
