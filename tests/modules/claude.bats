#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "claude module installs settings.json symlink" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ "$(readlink "$HOME/.claude/settings.json")" = "$GOODIES_ROOT/modules/claude/settings.json" ]
}

@test "claude module installs command symlinks" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/commands/goodies-watch.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-watch.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-watch.md" ]
    [ -L "$HOME/.claude/commands/goodies-distill.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-distill.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-distill.md" ]
    [ -L "$HOME/.claude/commands/goodies-bkm.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-bkm.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-bkm.md" ]
}

@test "claude module installs snippets symlink" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/snippets" ]
    [ "$(readlink "$HOME/.claude/snippets")" = "$GOODIES_ROOT/modules/claude/snippets" ]
}

@test "claude module removes broken legacy symlinks" {
    mkdir -p "$HOME/.claude/commands"
    ln -s "/nonexistent/watch-pr.md" "$HOME/.claude/commands/watch-pr.md"
    ln -s "/nonexistent/distill.md" "$HOME/.claude/commands/distill.md"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ ! -e "$HOME/.claude/commands/watch-pr.md" ]
    [ ! -e "$HOME/.claude/commands/distill.md" ]
}

@test "claude module creates required directories" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -d "$HOME/.claude/commands" ]
}

@test "claude module install is idempotent" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ -L "$HOME/.claude/commands/goodies-watch.md" ]
    [ -L "$HOME/.claude/commands/goodies-distill.md" ]
    [ -L "$HOME/.claude/commands/goodies-bkm.md" ]
}

@test "tampermonkey copilot-request-review userscript exists with valid metadata" {
    # The userscript is browser-side — not installed by install.sh.
    # This test guards the file's existence + critical metadata so a
    # silent rename or accidental deletion is caught.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    [ -f "$script" ]
    # Use regex with tolerant whitespace so harmless alignment changes —
    # e.g. userscript-manager auto-formatting that adjusts the metadata
    # block's column alignment — don't break the tests. We match the
    # *semantic* content (directive name + value), not the exact spacing.
    #
    # Use POSIX `[[:space:]]` rather than `\s`. POSIX ERE does not
    # define `\s` — BSD grep (macOS default) treats it as a literal `s`,
    # silently mismatching. `[[:space:]]` is portable across GNU + BSD.
    grep -qE '^//[[:space:]]*==UserScript==' "$script"
    grep -qE '^//[[:space:]]*@match[[:space:]]+https://github\.com/\*/\*/pull/\*' "$script"
    grep -qE '^//[[:space:]]*@name[[:space:]]+goodies:[[:space:]]+Copilot auto-request-review' "$script"
}

@test "tampermonkey userscript uses MutationObserver (push detection, not page-load only)" {
    # Push detection is the script's primary trigger; without the
    # observer, users would have to refresh the tab on every push.
    # Guard against accidental regression to page-load-only triggering.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF "MutationObserver" "$script"
    grep -qF "TIMELINE_SELECTORS" "$script"
}

@test "tampermonkey userscript matches button by visible text (not aria-label)" {
    # Visible text is more robust than aria-label or class names.
    # Guard against silent regression to aria-label matching.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF "REQUEST_BUTTON_TEXTS" "$script"
    grep -qF "textContent" "$script"
    # And that we're NOT relying on aria-label as the primary match
    # axis. The previous narrow guard (just one quote-flavor + just
    # querySelector + just `button` element) missed common variants.
    # Broader regex catches:
    #   querySelector / querySelectorAll
    #   single or double quotes around the selector
    #   any element prefix (button, a, [role="button"], etc.) before
    #     the [aria-label] attribute selector
    # If aria-label matching ever sneaks back in via any of these forms,
    # the test fails — which is the regression-guard intent.
    #
    # The `aria-label` *string* may legitimately appear in comments
    # explaining why we DON'T use it. So we don't ban the substring
    # itself; we ban its use inside an attribute selector.
    ! grep -qE "querySelector(All)?\([\"'][^\"']*\[aria-label" "$script"
}

@test "tampermonkey userscript has per-tab status panel + action log" {
    # Layer A observability + per-tab status UI: a colored dot + an
    # expandable panel showing this tab's filtered log + a "Copy log"
    # button so users can paste a bug report without opening DevTools.
    # Each tab is fully independent: the dot reflects this tab's
    # in-memory state machine, NOT the cross-tab localStorage mix.
    # Guard against accidental regression.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"

    # The persistent action log (Layer A) — ring buffer in localStorage.
    grep -qF "LOG_KEY" "$script"
    grep -qF "LOG_MAX_ENTRIES" "$script"
    grep -qF "function appendLog" "$script"
    grep -qF "tab_id: TAB_ID" "$script"

    # DevTools investigation hook for the rare cross-tab path.
    grep -qF "__goodiesActionLog" "$script"

    # Per-tab status state machine (two colors only — green/red).
    # The hover tooltip names the precise label under the hood.
    grep -qF "setTabStatus" "$script"
    grep -qF "tabStatus" "$script"

    # Panel UI: dot + expandable body + copy/clear buttons.
    grep -qF "PANEL_DOT_ID" "$script"
    grep -qF "PANEL_BODY_ID" "$script"
    grep -qF "copyTabLog" "$script"
    grep -qF "clearTabLog" "$script"

    # Per-tab filtering — copying / showing log MUST filter to this
    # tab's entries. Mixing other tabs' history into this tab's UI
    # would confuse the user about which tab failed.
    grep -qF "getTabFilteredLog" "$script"
    grep -qE 'tab_id[[:space:]]*===[[:space:]]*TAB_ID' "$script"
}

@test "tampermonkey userscript NO yellow/degraded status (binary green/red only)" {
    # Two-tier status by design: green = working as intended, red =
    # NOT doing its job. Yellow / "degraded" papers over real failures
    # with a softer color and would invite the user to ignore them.
    # Guard against accidental drift back to a multi-tier model.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    # The setTabStatus callsites must use only green/red as first arg.
    # `setTabStatus('yellow', ...)` or `setTabStatus('gray', ...)` would
    # be a regression. (gray is fine in the toast — flashIndicator —
    # which is informational, not a status indicator. Different concept.)
    ! grep -qE "setTabStatus\([\"']yellow[\"']" "$script"
    ! grep -qE "setTabStatus\([\"']gray[\"']" "$script"
    ! grep -qE "setTabStatus\([\"']orange[\"']" "$script"
}

@test "tampermonkey directory has README" {
    [ -f "$GOODIES_ROOT/modules/claude/scripts/tampermonkey/README.md" ]
}

@test "tampermonkey userscript NOT installed by install.sh" {
    # Userscripts live in browser extensions; install.sh must not
    # symlink them anywhere on the filesystem.
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ ! -e "$HOME/.claude/scripts" ]
    [ ! -e "$HOME/.claude/copilot-request-review.user.js" ]
    # And the source file is still where it should be (not moved).
    [ -f "$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js" ]
}

@test "claude module skips existing regular settings.json" {
    mkdir -p "$HOME/.claude"
    echo '{"custom": true}' > "$HOME/.claude/settings.json"
    run bash "$GOODIES_ROOT/modules/claude/install.sh"
    assert_success
    [ ! -L "$HOME/.claude/settings.json" ]
    grep -q '"custom"' "$HOME/.claude/settings.json"
}

@test "claude module installs env.sh symlink to bashrc.d" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.bashrc.d/claude.sh" ]
    [ "$(readlink "$HOME/.bashrc.d/claude.sh")" = "$GOODIES_ROOT/modules/claude/env.sh" ]
}

# --- env.sh tests ---

@test "env.sh defines claude function when no alias exists" {
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && type -t claude'
    assert_success
    assert_output "function"
}

@test "env.sh claude function fails when token file missing" {
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && claude --version 2>&1'
    assert_failure
    assert_output --partial "not found or empty"
}

@test "env.sh claude function fails when token file is empty" {
    touch "$HOME/.claude_bedrock_token"
    run bash -c 'source "$GOODIES_ROOT/modules/claude/env.sh" && claude --version 2>&1'
    assert_failure
    assert_output --partial "not found or empty"
}

@test "env.sh claude function sets environment variables correctly" {
    echo "test-token-123" > "$HOME/.claude_bedrock_token"
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'FAKE'
#!/bin/bash
echo "REGION=$AWS_REGION"
echo "BEDROCK=$CLAUDE_CODE_USE_BEDROCK"
echo "TOKEN=$AWS_BEARER_TOKEN_BEDROCK"
FAKE
    chmod +x "$HOME/bin/claude"
    run bash -c '
        export PATH="$HOME/bin:$PATH"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        claude
    '
    assert_success
    assert_line "REGION=us-east-2"
    assert_line "BEDROCK=1"
    assert_line "TOKEN=test-token-123"
}

@test "env.sh strips trailing newline from token" {
    printf "my-token\n" > "$HOME/.claude_bedrock_token"
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'FAKE'
#!/bin/bash
printf "TOKEN=%s\n" "$AWS_BEARER_TOKEN_BEDROCK"
FAKE
    chmod +x "$HOME/bin/claude"
    run bash -c '
        export PATH="$HOME/bin:$PATH"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        claude
    '
    assert_success
    assert_output "TOKEN=my-token"
}

@test "env.sh overrides alias silently in non-interactive shell" {
    run bash -c '
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        type -t claude
    '
    assert_success
    assert_output "function"
}

@test "env.sh removes alias when overriding" {
    run bash -c '
        shopt -s expand_aliases
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh"
        alias claude 2>&1
    '
    assert_failure
}

@test "env.sh does not prompt in non-interactive shell (no TTY)" {
    run bash -c '
        alias claude="echo old-alias"
        source "$GOODIES_ROOT/modules/claude/env.sh" 2>&1
    '
    assert_success
    refute_output --partial "Override with goodies"
}

@test "env.sh interactive prompt defaults to override on empty input" {
    run bash -c '
        echo "" | bash -c '\''
            shopt -s expand_aliases
            alias claude="echo old"
            source <(sed "s/\[\[ -t 0 && -t 1 \]\]/true/" "$GOODIES_ROOT/modules/claude/env.sh") 2>/dev/null
            type -t claude
        '\''
    '
    assert_success
    assert_output "function"
}

@test "env.sh interactive prompt skips function on N input" {
    run bash -c '
        echo "n" | bash -c '\''
            shopt -s expand_aliases
            alias claude="echo old"
            source <(sed "s/\[\[ -t 0 && -t 1 \]\]/true/" "$GOODIES_ROOT/modules/claude/env.sh") 2>/dev/null
            type -t claude 2>/dev/null || echo "not-defined"
        '\''
    '
    assert_success
    assert_output "alias"
}
