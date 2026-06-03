#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "tmux module installs .tmux.conf symlink" {
    bash "$GOODIES_ROOT/modules/tmux/install.sh"
    [ -L "$HOME/.tmux.conf" ]
    [ "$(readlink "$HOME/.tmux.conf")" = "$GOODIES_ROOT/modules/tmux/.tmux.conf" ]
}

@test "tmux module creates plugins directory and links tpm" {
    bash "$GOODIES_ROOT/modules/tmux/install.sh"
    [ -d "$HOME/.tmux/plugins" ]
    [ -L "$HOME/.tmux/plugins/tpm" ]
    [ "$(readlink "$HOME/.tmux/plugins/tpm")" = "$GOODIES_ROOT/modules/tmux/tpm" ]
}

@test "tmux module install is idempotent" {
    bash "$GOODIES_ROOT/modules/tmux/install.sh"
    bash "$GOODIES_ROOT/modules/tmux/install.sh"
    [ -L "$HOME/.tmux.conf" ]
    [ -L "$HOME/.tmux/plugins/tpm" ]
}
