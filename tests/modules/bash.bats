#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "bash module installs .bash_aliases symlink" {
    bash "$GOODIES_ROOT/modules/bash/install.sh"
    [ -L "$HOME/.bash_aliases" ]
    [ "$(readlink "$HOME/.bash_aliases")" = "$GOODIES_ROOT/modules/bash/.bash_aliases" ]
}

@test "bash module install is idempotent" {
    bash "$GOODIES_ROOT/modules/bash/install.sh"
    bash "$GOODIES_ROOT/modules/bash/install.sh"
    [ -L "$HOME/.bash_aliases" ]
    local count
    count=$(find "$HOME" -name ".bash_aliases" | wc -l)
    [ "$count" -eq 1 ]
}

@test "bash module skips existing regular .bash_aliases file" {
    echo "custom content" > "$HOME/.bash_aliases"
    run bash "$GOODIES_ROOT/modules/bash/install.sh"
    [ ! -L "$HOME/.bash_aliases" ]
    [ "$(cat "$HOME/.bash_aliases")" = "custom content" ]
}
