#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_home
    source "$GOODIES_ROOT/lib/goodies-lib.sh"
}

teardown() {
    teardown_test_home
}

# --- safe_link tests ---

@test "safe_link creates symlink to target" {
    local src="$GOODIES_ROOT/lib/goodies-lib.sh"
    local dst="$HOME/test-link"
    run safe_link "$src" "$dst"
    assert_success
    [ -L "$dst" ]
    [ "$(readlink "$dst")" = "$src" ]
}

@test "safe_link overwrites existing symlink" {
    local src="$GOODIES_ROOT/lib/goodies-lib.sh"
    local dst="$HOME/test-link"
    ln -s /nonexistent "$dst"
    run safe_link "$src" "$dst"
    assert_success
    [ "$(readlink "$dst")" = "$src" ]
}

@test "safe_link skips existing regular file" {
    local src="$GOODIES_ROOT/lib/goodies-lib.sh"
    local dst="$HOME/test-file"
    echo "existing content" > "$dst"
    run safe_link "$src" "$dst"
    assert_failure
    assert_output --partial "exists as a regular file"
    [ ! -L "$dst" ]
    [ "$(cat "$dst")" = "existing content" ]
}

# --- ensure_dir tests ---

@test "ensure_dir creates nested directories" {
    local dir="$HOME/a/b/c"
    run ensure_dir "$dir"
    assert_success
    [ -d "$dir" ]
}

@test "ensure_dir is idempotent" {
    local dir="$HOME/existing"
    mkdir -p "$dir"
    run ensure_dir "$dir"
    assert_success
    [ -d "$dir" ]
}

# --- path_append tests ---

@test "path_append adds entry to bashrc" {
    local bashrc="$HOME/.bashrc"
    touch "$bashrc"
    run path_append "$bashrc" "/opt/tools"
    assert_success
    grep -qxF 'export PATH=${PATH}:/opt/tools' "$bashrc"
}

@test "path_append is idempotent" {
    local bashrc="$HOME/.bashrc"
    touch "$bashrc"
    path_append "$bashrc" "/opt/tools"
    path_append "$bashrc" "/opt/tools"
    local count
    count=$(grep -cxF 'export PATH=${PATH}:/opt/tools' "$bashrc")
    [ "$count" -eq 1 ]
}

@test "path_append handles missing bashrc" {
    local bashrc="$HOME/.bashrc"
    run path_append "$bashrc" "/opt/new"
    assert_success
    grep -qxF 'export PATH=${PATH}:/opt/new' "$bashrc"
}

# --- platform detection tests ---

@test "is_linux or is_macos returns true on current platform" {
    if [[ "$(uname -s)" == "Linux" ]]; then
        run is_linux
        assert_success
        run is_macos
        assert_failure
    else
        run is_macos
        assert_success
        run is_linux
        assert_failure
    fi
}

# --- require_cmd tests ---

@test "require_cmd succeeds for existing command" {
    run require_cmd bash
    assert_success
}

@test "require_cmd fails for missing command" {
    run require_cmd nonexistent_command_xyz
    assert_failure
    assert_output --partial "not found"
}
