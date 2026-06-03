#!/bin/bash

# Shared test helper for all BATS tests

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="$TESTS_DIR/bats"

load "$BATS_DIR/bats-support/load"
load "$BATS_DIR/bats-assert/load"

export GOODIES_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

setup_test_home() {
    export ORIG_HOME="$HOME"
    export HOME="$BATS_TMPDIR/home_$$_$BATS_TEST_NUMBER"
    mkdir -p "$HOME"
}

teardown_test_home() {
    rm -rf "$HOME"
    export HOME="$ORIG_HOME"
}
