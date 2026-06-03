#!/bin/bash

# Shared test helper for all BATS tests

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="$TESTS_DIR/bats"

load "$BATS_DIR/bats-support/load"
load "$BATS_DIR/bats-assert/load"

export GOODIES_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

setup_test_home() {
    export ORIG_HOME="$HOME"
    TEST_HOME="$BATS_TMPDIR/home_$$_$BATS_TEST_NUMBER"
    mkdir -p "$TEST_HOME"
    export HOME="$TEST_HOME"
}

teardown_test_home() {
    export HOME="$ORIG_HOME"
    if [ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && [[ "$TEST_HOME" == "$BATS_TMPDIR"/* ]]; then
        rm -rf "$TEST_HOME"
    fi
}
