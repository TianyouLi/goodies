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
    assert_success
    [ ! -L "$HOME/.emacs" ]
    [ "$(cat "$HOME/.emacs")" = "custom emacs config" ]
}

@test ".emacs contains claude-code.el integration block" {
    # Guards against accidental removal of the Claude Code integration.
    # The block is gated on (>= emacs-major-version 30) so older Emacs
    # silently skips it; the assertion is on the source-of-truth file.
    # Use grep -F (fixed strings) so '.' in "claude-code.el" matches a
    # literal dot rather than any character.
    grep -qF "claude-code.el" "$GOODIES_ROOT/modules/emacs/.emacs"
    grep -qF "use-package claude-code" "$GOODIES_ROOT/modules/emacs/.emacs"
    grep -qF "claude-code-command-map" "$GOODIES_ROOT/modules/emacs/.emacs"
}
