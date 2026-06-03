#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "emacs module installs .emacs symlink" {
    bash "$GOODIES_ROOT/modules/emacs/install.sh"
    [ -L "$HOME/.emacs" ]
    [ "$(readlink "$HOME/.emacs")" = "$GOODIES_ROOT/modules/emacs/.emacs" ]
}

@test "emacs module install is idempotent" {
    bash "$GOODIES_ROOT/modules/emacs/install.sh"
    bash "$GOODIES_ROOT/modules/emacs/install.sh"
    [ -L "$HOME/.emacs" ]
}

@test "emacs module skips existing regular .emacs file" {
    echo "custom emacs config" > "$HOME/.emacs"
    run bash "$GOODIES_ROOT/modules/emacs/install.sh"
    [ ! -L "$HOME/.emacs" ]
    [ "$(cat "$HOME/.emacs")" = "custom emacs config" ]
}
