#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "git module installs git-completion symlink" {
    bash "$GOODIES_ROOT/modules/git/install.sh"
    [ -L "$HOME/.git_env/git-completion.bash" ]
    [ "$(readlink "$HOME/.git_env/git-completion.bash")" = "$GOODIES_ROOT/modules/git/env/git-completion.bash" ]
}

@test "git module installs git-prompt symlink" {
    bash "$GOODIES_ROOT/modules/git/install.sh"
    [ -L "$HOME/.git_env/git-prompt.sh" ]
    [ "$(readlink "$HOME/.git_env/git-prompt.sh")" = "$GOODIES_ROOT/modules/git/env/git-prompt.sh" ]
}

@test "git module installs git-clang-format to ~/.local/bin" {
    bash "$GOODIES_ROOT/modules/git/install.sh"
    [ -L "$HOME/.local/bin/git-clang-format" ]
    [ "$(readlink "$HOME/.local/bin/git-clang-format")" = "$GOODIES_ROOT/modules/git/git-clang-format" ]
}

@test "git module install is idempotent" {
    bash "$GOODIES_ROOT/modules/git/install.sh"
    bash "$GOODIES_ROOT/modules/git/install.sh"
    [ -L "$HOME/.git_env/git-completion.bash" ]
    [ -L "$HOME/.git_env/git-prompt.sh" ]
    [ -L "$HOME/.local/bin/git-clang-format" ]
}
