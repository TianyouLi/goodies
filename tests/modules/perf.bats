#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "perf module adds PATH entry to .bashrc" {
    bash "$GOODIES_ROOT/modules/perf/install.sh"
    grep -q "modules/perf" "$HOME/.bashrc"
}

@test "perf module PATH entry is idempotent" {
    bash "$GOODIES_ROOT/modules/perf/install.sh"
    bash "$GOODIES_ROOT/modules/perf/install.sh"
    local count
    count=$(grep -c "modules/perf" "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}
