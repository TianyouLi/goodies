#!/bin/bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="$TESTS_DIR/bats/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
    echo "ERROR: bats not found. Run: git submodule update --init --recursive"
    exit 1
fi

"$BATS" "$TESTS_DIR" "$@"
