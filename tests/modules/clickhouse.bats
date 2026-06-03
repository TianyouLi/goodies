#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "clickhouse module adds scripts PATH entry to .bashrc" {
    bash "$GOODIES_ROOT/modules/clickhouse/install.sh"
    grep -q "modules/clickhouse/scripts" "$HOME/.bashrc"
}

@test "clickhouse module PATH entry is idempotent" {
    bash "$GOODIES_ROOT/modules/clickhouse/install.sh"
    bash "$GOODIES_ROOT/modules/clickhouse/install.sh"
    local count
    count=$(grep -c "modules/clickhouse/scripts" "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}
