#!/bin/bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="$TESTS_DIR/bats/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
    echo "ERROR: bats not found. Run: git submodule update --init --recursive"
    exit 1
fi

# Pass explicit test paths instead of just "$TESTS_DIR" so per-module tests
# under tests/modules/ are picked up. Plain `bats <dir>` is non-recursive,
# and `bats -r <dir>` would also walk into the bats-core/-support/-assert
# submodules' own test suites under tests/bats/ (which fail under our setup).
"$BATS" "$TESTS_DIR/modules" "$TESTS_DIR/integration.bats" "$TESTS_DIR/lib.bats" "$@"
