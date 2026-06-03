#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "kernel module adds PATH entry to .bashrc" {
    bash "$GOODIES_ROOT/modules/kernel/install.sh"
    grep -qxF "export PATH=\${PATH}:$GOODIES_ROOT/modules/kernel" "$HOME/.bashrc"
}

@test "kernel module PATH entry is idempotent" {
    bash "$GOODIES_ROOT/modules/kernel/install.sh"
    bash "$GOODIES_ROOT/modules/kernel/install.sh"
    local count
    count=$(grep -cxF "export PATH=\${PATH}:$GOODIES_ROOT/modules/kernel" "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}
