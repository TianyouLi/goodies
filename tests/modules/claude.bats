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
    [ -L "$HOME/.claude/commands/goodies-review.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-review.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-review.md" ]
    [ -L "$HOME/.claude/commands/goodies-feedback.md" ]
    [ "$(readlink "$HOME/.claude/commands/goodies-feedback.md")" = "$GOODIES_ROOT/modules/claude/commands/goodies-feedback.md" ]
}

@test "claude module installs every goodies-*.md command by glob (no hand list)" {
    # Guards the 'automatic for new commands' property: the installer must
    # symlink ALL commands/goodies-*.md, so a future command is installed
    # without editing install.sh. Compare the source set to the linked set.
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    for src in "$GOODIES_ROOT"/modules/claude/commands/goodies-*.md; do
        local base; base="$(basename "$src")"
        [ -L "$HOME/.claude/commands/$base" ]
        [ "$(readlink "$HOME/.claude/commands/$base")" = "$src" ]
    done
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

@test "claude module installs goodies-feedback trigger into CLAUDE.md" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -f "$HOME/.claude/CLAUDE.md" ]
    grep -qF "BEGIN goodies-feedback" "$HOME/.claude/CLAUDE.md"
    grep -qF "END goodies-feedback" "$HOME/.claude/CLAUDE.md"
    # Keyed off the namespace, and routes to the shared command.
    grep -qF 'goodies-*' "$HOME/.claude/CLAUDE.md"
    grep -qF "/goodies-feedback" "$HOME/.claude/CLAUDE.md"
}

@test "goodies-feedback trigger block is idempotent (no duplication on re-install)" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    local n; n=$(grep -c "BEGIN goodies-feedback" "$HOME/.claude/CLAUDE.md")
    [ "$n" -eq 1 ]
}

@test "goodies-feedback trigger re-install works without python3 (awk path)" {
    # The re-install (block-refresh) path must not depend on python3 — minimal
    # systems may lack it. Mask python3/python from PATH and confirm a re-install
    # still refreshes the single block idempotently and exits success.
    bash "$GOODIES_ROOT/modules/claude/install.sh"   # first install
    local shim; shim="$(mktemp -d)"
    cat > "$shim/python3" <<'SH'
#!/bin/sh
echo "python3 should not be called by install.sh" >&2
exit 127
SH
    cp "$shim/python3" "$shim/python"
    chmod +x "$shim/python3" "$shim/python"
    PATH="$shim:$PATH" run bash "$GOODIES_ROOT/modules/claude/install.sh"
    rm -rf "$shim"
    [ "$status" -eq 0 ]
    local n; n=$(grep -c "BEGIN goodies-feedback" "$HOME/.claude/CLAUDE.md")
    [ "$n" -eq 1 ]
    grep -qF "END goodies-feedback" "$HOME/.claude/CLAUDE.md"
}

@test "goodies-feedback trigger preserves pre-existing CLAUDE.md content" {
    mkdir -p "$HOME/.claude"
    printf '# my notes\n\nkeep this line\n' > "$HOME/.claude/CLAUDE.md"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    grep -qF "keep this line" "$HOME/.claude/CLAUDE.md"
    grep -qF "BEGIN goodies-feedback" "$HOME/.claude/CLAUDE.md"
}

@test "goodies-feedback trigger refresh handles indented markers" {
    # The awk refresh matches markers anywhere on the line (not just column 1),
    # so a marker indented by a user/formatter is still replaced rather than
    # silently left stale + duplicated. Indent the installed markers, re-install,
    # and confirm exactly one (un-indented) block results.
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    sed -i.bak 's/^<!-- BEGIN goodies-feedback/    <!-- BEGIN goodies-feedback/; s/^<!-- END goodies-feedback/    <!-- END goodies-feedback/' "$HOME/.claude/CLAUDE.md" && rm -f "$HOME/.claude/CLAUDE.md.bak"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    local n; n=$(grep -c "BEGIN goodies-feedback" "$HOME/.claude/CLAUDE.md")
    [ "$n" -eq 1 ]
    # the refreshed block is emitted at column 1 (no stale indented marker left)
    ! grep -qE '^[[:space:]]+<!-- BEGIN goodies-feedback' "$HOME/.claude/CLAUDE.md"
}

@test "goodies-feedback refresh does not truncate on BEGIN-without-END" {
    # If the managed block is malformed (BEGIN present, END missing), the awk
    # refresh must NOT drop everything after BEGIN to EOF. It should bail
    # (END{} exit 1 -> refresh fails) and leave the file intact, preserving the
    # user's content that followed the dangling BEGIN.
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    # remove the END marker, then append user content after the dangling block
    sed -i.bak '/END goodies-feedback/d' "$HOME/.claude/CLAUDE.md" && rm -f "$HOME/.claude/CLAUDE.md.bak"
    printf '\n# IMPORTANT USER CONTENT\nkeep me\n' >> "$HOME/.claude/CLAUDE.md"
    run bash "$GOODIES_ROOT/modules/claude/install.sh"
    # install.sh ends with `true`, so overall exit is 0; the guarantee we assert
    # is that the user content survived (no truncation) and no temp file leaked.
    grep -qF "keep me" "$HOME/.claude/CLAUDE.md"
    [ -z "$(ls "$HOME/.claude/CLAUDE.md.goodies."* 2>/dev/null)" ]
}

@test "goodies-feedback command markdown contains required sections" {
    local f="$GOODIES_ROOT/modules/claude/commands/goodies-feedback.md"
    [ -f "$f" ]
    grep -qF "allowed-tools:" "$f"
    grep -qF "gh issue create" "$f"
    grep -qF "reactions" "$f"          # the vote mechanism
    grep -qF "cmd:" "$f"               # per-command label scoping
    grep -qF '(y)es, (n)o, (e)dit' "$f" # confirm-before-post
}

@test "claude module install is idempotent" {
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    bash "$GOODIES_ROOT/modules/claude/install.sh"
    [ -L "$HOME/.claude/settings.json" ]
    [ -L "$HOME/.claude/commands/goodies-watch.md" ]
    [ -L "$HOME/.claude/commands/goodies-distill.md" ]
    [ -L "$HOME/.claude/commands/goodies-bkm.md" ]
    [ -L "$HOME/.claude/commands/goodies-review.md" ]
}

@test "goodies-review command markdown contains required sections" {
    # Guard against accidental removal of key sections from the command
    # markdown. These are the structural anchors the LLM runtime depends on.
    grep -qF "Run the gatekeeper" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
    grep -qF "[review-pr /" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
    grep -qF "First-time banner" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
    grep -qF "active-context.json" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
    grep -qF "allowed-tools:" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
    grep -qF "confidence:" "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
}

@test "goodies-review per-layer guidance files exist and are wired into --engage" {
    # --engage loads pattern guidance from goodies-review/layers/<layer>.md at
    # runtime. Guard both halves of that dependency so a future rename/move of
    # the files (or the path logic) can't silently break the engagement step:
    #   1. all five layer files are present
    #   2. the command markdown still references the layers/<layer>.md path
    local layers_dir="$GOODIES_ROOT/modules/claude/commands/goodies-review/layers"
    for layer in problem direction design tradeoff implementation; do
        [ -f "$layers_dir/$layer.md" ]
    done
    grep -qF 'goodies-review/layers/<layer>.md' "$GOODIES_ROOT/modules/claude/commands/goodies-review.md"
}

@test "goodies-review layer docs link to references.md and the file exists" {
    # Each layer doc cites sources with [n] markers that resolve against the
    # shared references.md (which is NOT loaded at runtime). Guard the file's
    # existence and that every layer back-links to its section, so a rename of
    # references.md doesn't leave dangling citation links.
    local review_dir="$GOODIES_ROOT/modules/claude/commands/goodies-review"
    [ -f "$review_dir/references.md" ]
    for layer in problem direction design tradeoff implementation; do
        grep -qF "../references.md#${layer}-layer" "$review_dir/layers/$layer.md"
        # references.md must contain the section heading the link targets
        grep -qiF "## ${layer} layer" "$review_dir/references.md"
    done
}

@test "goodies-review design doc declares 5-layer hierarchy" {
    # Guard the design doc separately from the command markdown so a failure
    # makes it obvious which file regressed.
    grep -qF "5-layer hierarchy" "$GOODIES_ROOT/docs/design/goodies-review.md" || \
        grep -qF "5 layers" "$GOODIES_ROOT/docs/design/goodies-review.md"
}

@test "tampermonkey copilot click-trigger userscript exists with valid metadata" {
    # The userscript is browser-side — not installed by install.sh.
    # Guards the file's existence + critical metadata so a silent
    # rename or accidental deletion is caught. Regex uses POSIX
    # [[:space:]] (BSD grep treats `\s` as literal s).
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    [ -f "$script" ]
    grep -qE '^//[[:space:]]*==UserScript==' "$script"
    grep -qE '^//[[:space:]]*@match[[:space:]]+https://github\.com/\*/\*/pull/\*' "$script"
    # v1.0 name: "goodies: Copilot click-trigger"
    grep -qE '^//[[:space:]]*@name[[:space:]]+goodies:[[:space:]]+Copilot click-trigger' "$script"
    # at least 1.x — the v1.x line (vs v0.x archaeology)
    grep -qE '^//[[:space:]]*@version[[:space:]]+1\.' "$script"

    # Anti-regression: SCRIPT_VERSION_FOR_REPORT MUST match @version.
    # v1.3 shipped with a mismatch (header v1.3.0, internal constant
    # v1.2.0) which made bug reports misleading. Compare both values
    # so any future bump must update both consistently.
    local meta_ver internal_ver
    meta_ver=$(grep -E '^//[[:space:]]*@version' "$script" | awk '{print $NF}')
    internal_ver=$(grep -oE "SCRIPT_VERSION_FOR_REPORT[[:space:]]*=[[:space:]]*'[^']*'" "$script" | head -1 | grep -oE "'[^']*'" | tr -d "'")
    [ "$meta_ver" = "$internal_ver" ]
}

@test "tampermonkey userscript v1.x reads marker via DOM scan (zero gh API)" {
    # v1.3 design: zero gh API in the userscript. Watcher writes a
    # <details>-wrapped marker (which survives markdown render); the
    # userscript scans the rendered description's textContent for
    # the marker payload. Free, scales to unlimited tabs, no rate
    # limit. (v1.0 tried HTML-comment markers + DOM scrape — comments
    # got stripped. v1.1/v1.2 tried API fetch + ETag — hit the 60/hr
    # anonymous rate limit. v1.3 = different marker form + DOM scan.)
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF "MARKER_REGEX" "$script"
    grep -qF "goodies-watch:click-request-review" "$script"
    grep -qF "POLL_INTERVAL_MS" "$script"
    grep -qF "function scanForMarker" "$script"
    grep -qF "function pollDom" "$script"
    grep -qF "function readPRBodyText" "$script"
    grep -qF "PR_BODY_SELECTORS" "$script"
    # v1.4: button finder uses GitHub's re_request_reviewer_id form
    # name (most reliable signal — survives icon-only rendering).
    grep -qF 're_request_reviewer_id' "$script"
    grep -qF 'function ancestorMentionsCopilot' "$script"
    # v1.3 hard rule: zero api.github.com calls anywhere in the script.
    # Historical comments mention the domain (design rationale), so check
    # only non-comment lines for actual code usage.
    # Use '^ *//' (POSIX) not '^\s*//' (\s is literal 's' in POSIX grep).
    ! grep -v '^ *//' "$script" | grep -qF "api.github.com"
    ! grep -v '^ *//' "$script" | grep -qF "fetch("
    # Anti-regression: v1.1/1.2 API constants must NOT be back.
    ! grep -qF "function pollApi" "$script"
    ! grep -qF "function getPRApiUrl" "$script"
    ! grep -qF "function isCopilotPending" "$script"
    ! grep -qF "If-None-Match" "$script"
    ! grep -qF "lastEtag" "$script"
    ! grep -qF "/requested_reviewers" "$script"
    # Anti-regression: v0.x DOM heuristics must NOT be back.
    ! grep -qF "COPILOT_BUSY_MARKERS" "$script"
    ! grep -qF "COPILOT_REVIEWED_MARKERS" "$script"
    ! grep -qF "THREAD_RESOLVED_MARKERS" "$script"
    ! grep -qF "TIMELINE_SELECTORS" "$script"
    ! grep -qF "PUSH_MARKERS" "$script"
    ! grep -qF "MutationObserver" "$script"
    # Anti-regression: v1.3 dropped all skew computation (earlier versions tried
    # an API HEAD probe then a <relative-time> DOM-derive; both had problems).
    # Guard that the actual skew mechanisms are gone — not just the string, since
    # the explanatory comments intentionally keep the history in prose.
    # refreshSkew was the scheduled function that performed skew updates.
    # skewMs was the live variable storing the computed offset.
    ! grep -qF "function refreshSkew" "$script"
    ! grep -qF "skewMs =" "$script"
    ! grep -qF "let skewMs" "$script"
    ! grep -qF "var skewMs" "$script"
}

@test "tampermonkey userscript does not pin button match to aria-label value" {
    # Originally (v0.x) we banned ANY `querySelector('...[aria-label...')`
    # because we wanted visible-text matching to be primary.
    # v1.4 broadens: button finder uses three strategies (form name,
    # textContent + aria-label/title combined haystack, with ancestor
    # discovery via `querySelectorAll('[alt], [aria-label], ...')`).
    # The test's intent — don't pin to a specific aria-label VALUE —
    # is preserved. What's banned: `querySelector('button[aria-label="re-request review"]')`-style.
    # What's allowed: `querySelectorAll('[aria-label]')` for attribute discovery.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF "REQUEST_BUTTON_TEXTS" "$script"
    grep -qF "textContent" "$script"
    # Ban: a selector that matches an aria-label with a SPECIFIC VALUE
    # (the brittle pattern). Allow: querying for ANY element WITH an
    # aria-label attribute (the discovery pattern v1.4 uses).
    ! grep -qE "querySelector(All)?\([\"'][^\"']*\[aria-label[[:space:]]*=" "$script"
}

@test "tampermonkey userscript Strategy 1 selector restricted to button, not input" {
    # v1.4.3: hidden inputs share re_request_reviewer_id but have
    # zero-size bounding boxes — they would cause false "button-unclickable"
    # failures even when the real submit button is present. Restrict to
    # button elements only.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'button[name="re_request_reviewer_id"]' "$script"
    ! grep -qF 'input[name="re_request_reviewer_id"]' "$script"
}

@test "tampermonkey userscript isOnPRPage restricted to conversation root" {
    # v1.4.4: /files, /commits, /checks sub-routes don't render the PR
    # description in the same DOM position, so the marker scan would
    # silently find nothing. Restrict to the conversation root only.
    # Guard: the regex must NOT include (?:/|$) (which allows sub-paths)
    # and MUST end with \/?$.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'PR_PATH_REGEX' "$script"
    grep -qF 'function isOnPRPage' "$script"
    # The regex must use a strict end-anchor, not (?:/|$) which allows sub-routes.
    ! grep -qF '(?:\/|$)' "$script"
    grep -qE 'pull\\\/\\\\d\+\\\/\?\\$' "$script" || grep -qE "pull/\\\\d\+\\\\/?\\$" "$script" || grep -qF 'pull\/\d+\/?$' "$script"
}

@test "tampermonkey userscript TAB_ID persisted in sessionStorage" {
    # v1.4.4: TAB_ID must survive page reloads (introduced in v1.4.2's
    # stale-DOM reload path). Persistence in sessionStorage ensures the
    # per-tab log filter and acted-nonce tracking remain coherent after
    # the reload — without it, the post-reload tab appears as a fresh
    # unknown-id tab and prior log entries are invisible.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'TAB_ID_SESSION_KEY' "$script"
    grep -qF 'sessionStorage' "$script"
    grep -qF 'sessionStorage.getItem' "$script"
    grep -qF 'sessionStorage.setItem' "$script"
}

@test "tampermonkey userscript clearTabLog uses per-tab cutoff, not shared buffer rewrite" {
    # v1.4.4: clearTabLog() previously rewrote the shared LOG_KEY buffer
    # which races with concurrent appendLog() calls from other tabs.
    # Fixed by recording a per-tab clear-cutoff timestamp; getTabFilteredLog
    # respects the cutoff without touching the shared buffer.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'TAB_CLEAR_KEY' "$script"
    grep -qF 'function setTabClearCutoff' "$script"
    grep -qF 'function getTabClearCutoffMs' "$script"
    # clearTabLog must NOT rewrite LOG_KEY directly.
    # Extract lines of clearTabLog's body with awk and confirm LOG_KEY is absent.
    # (Piping grep -q into grep is broken: -q suppresses stdout, so the second
    # grep always sees empty input. Use awk to extract the function body instead.)
    ! awk '/function clearTabLog/,/^[[:space:]]*}/' "$script" | grep -qF "localStorage.setItem(LOG_KEY"
    # getTabFilteredLog must filter by cutoff.
    grep -qF 'getTabClearCutoffMs' "$script"
}

@test "tampermonkey userscript getTabClearCutoffMs guards against NaN" {
    # v1.4.5: new Date(invalidString).getTime() returns NaN; NaN comparisons
    # are always false so a corrupt cutoff would hide all log entries for the
    # tab. Guard with isNaN check and fall back to 0.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'function getTabClearCutoffMs' "$script"
    grep -qF 'isNaN' "$script"
    # The NaN guard must be inside the getTabClearCutoffMs function body.
    awk '/function getTabClearCutoffMs/,/^[[:space:]]*}/' "$script" | grep -qF 'isNaN'
}

@test "tampermonkey userscript TAB_CLEAR_KEY is pruned to a bounded size" {
    # v1.4.6: TAB_CLEAR_KEY stores a cutoff per tab-id. Without pruning the
    # map grows without bound across many tabs/reloads. setTabClearCutoff()
    # now keeps at most TAB_CLEAR_MAX_ENTRIES entries (newest-first) and
    # drops invalid timestamps. Guard that the constant and pruning logic exist.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'TAB_CLEAR_MAX_ENTRIES' "$script"
    # Pruning must be inside setTabClearCutoff function body.
    awk '/function setTabClearCutoff/,/^[[:space:]]*}/' "$script" | grep -qF 'TAB_CLEAR_MAX_ENTRIES'
    awk '/function setTabClearCutoff/,/^[[:space:]]*}/' "$script" | grep -qF 'slice'
}

@test "tampermonkey userscript pollDom flips red after sustained body-selector misses" {
    # v1.4.7: if readPRBodyText() returns nothing for BODY_MISS_WARN_THRESHOLD
    # consecutive polls (~25s), the selectors have likely broken due to a GitHub
    # DOM change. pollDom() should log the miss streak and flip the status red
    # instead of silently staying green (hiding the failure from users).
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'BODY_MISS_WARN_THRESHOLD' "$script"
    grep -qF 'bodyMissStreak' "$script"
    grep -qF 'body-selector-miss' "$script"
    grep -qF 'selector-broken' "$script"
    grep -qF 'body-selector-recovered' "$script"
}

@test "tampermonkey userscript attemptClick updates status on already-acted nonce" {
    # v1.4.7: when attemptClick() bails early because the (writer,nonce) was
    # already acted by another tab, it returned without calling setTabStatus.
    # This left the status panel showing stale state. Now explicitly sets
    # green/observing so the panel reflects the actual situation.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'already acted on this nonce' "$script"
    # The setTabStatus call must be inside the attemptClick function body,
    # specifically in the hasActed early-return branch.
    awk '/function attemptClick/,/^[[:space:]]*\}$/' "$script" | grep -qF 'already acted on this nonce'
}

@test "tampermonkey userscript marks all fresh markers acted after successful click" {
    # v1.4.10 / finding 3424923834: after clicking one marker, other watchers'
    # still-fresh markers remained unacted. On the next poll, scanForMarker
    # returned one of them; attemptClick found no button (already gone) and
    # flipped red. Fixed by calling recordAllFreshMarkers(bodyText) after a
    # successful click, so all sibling fresh markers are marked acted.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'function recordAllFreshMarkers' "$script"
    grep -qF 'recordAllFreshMarkers(bodyText)' "$script"
    # Must be guarded on hasActed(marker.writer, marker.nonce) so it only
    # runs when a click actually happened (not on the reload-recovery path).
    grep -qF 'hasActed(marker.writer, marker.nonce)' "$script"
    # recordAllFreshMarkers must appear within ~15 lines of attemptClick(marker).
    grep -En 'attemptClick\(marker\)|recordAllFreshMarkers\(bodyText\)' "$script" \
        | awk -F: '
            /attemptClick/ { click=$1 }
            /recordAllFreshMarkers/ { record=$1 }
            END { exit !(record > click && record - click < 15) }
        '
}

@test "tampermonkey userscript scanForMarker comment describes acted table as cross-tab" {
    # v1.4.9 / finding 3424900118: the comment inside scanForMarker described
    # the acted-nonce table as "this tab's localStorage" — misleading because
    # ACTED_KEY is shared across all tabs. Fixed to say "shared (cross-tab)".
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    # Guard the corrected phrase is inside the scanForMarker function body.
    awk '/function scanForMarker/,/^[[:space:]]*\}/' "$script" | grep -qF 'cross-tab'
    # Guard the misleading "this tab's localStorage acted" phrase is gone.
    ! awk '/function scanForMarker/,/^[[:space:]]*\}/' "$script" | grep -qF "this tab's localStorage acted"
}

@test "tampermonkey userscript all-acted status detail matches localStorage persistence" {
    # v1.4.9 / finding 3424900129: the SCAN_NULL_ALL_ACTED status detail said
    # "already acted this session" — misleading because the acted-nonce record
    # is persisted in localStorage (survives reloads, shared cross-tab).
    # Fixed to say "stored in localStorage; waiting for a new nonce".
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF 'stored in localStorage' "$script"
    ! grep -qF 'already acted this session' "$script"
}

@test "tampermonkey userscript grep comment-filter uses POSIX portable syntax" {
    # v1.4.8 / finding 3424848688: the Bats assertion that filters comment
    # lines before checking for api.github.com / fetch( used '^\s*//'  where
    # \s is treated as literal 's' in POSIX grep (not a whitespace class).
    # Fixed to use '^ *//' which works portably.
    # Guard that the test file no longer contains the non-portable form.
    local bats="$GOODIES_ROOT/tests/modules/claude.bats"
    ! grep -qF "grep -v '^\s*//" "$bats"
    grep -qF "grep -v '^ *//" "$bats"
}

@test "tampermonkey userscript attemptClick exception flips status red" {
    # v1.4.8 / finding 3424848766: when attemptClick() throws, the catch
    # block logged the error but left the status dot green. Fixed by calling
    # setTabStatus('red', ...) in the catch. Guard the call is present.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    # 'click-exception' is the status name set on throw.
    grep -qF "'click-exception'" "$script"
    # Must be inside the catch block that wraps attemptClick.
    awk '/try \{/{p=1} p && /attemptClick\(marker\)/{q=1} q && /catch \(e\)/{r=1} r && /click-exception/{found=1} /^[[:space:]]*\}$/ && r{r=0} END{exit !found}' "$script"
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

@test "tampermonkey userscript reloads page once when button not found (stale DOM recovery)" {
    # v1.4.2: when a fresh marker is present but no button is found, the
    # page is stale (loaded before the last push). Reload once per nonce
    # so the fresh DOM renders the re-request button. Avoid infinite loops:
    # the second attempt after reload goes to click-skipped-no-button.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    grep -qF "RELOAD_KEY" "$script"
    grep -qF "RELOAD_MAX_ENTRIES" "$script"
    grep -qF "function hasReloaded" "$script"
    grep -qF "function recordReload" "$script"
    grep -qF "reload-for-fresh-button" "$script"
    grep -qF "location.reload()" "$script"
    # Guard: reload is ONLY attempted when button is absent AND not yet reloaded.
    # After reload the hasReloaded check prevents a second reload loop.
    grep -qF "hasReloaded(marker.writer, marker.nonce)" "$script"
}

@test "tampermonkey userscript: binary green/red status (no yellow/gray)" {
    # v1.0 keeps v0.x's two-color model: green = working as designed,
    # red = NOT doing its job. The watcher won't post a marker on a
    # closed/merged PR (its Step 0 exits gracefully); a marker-less
    # script just stays green-observing, no special "gray" needed.
    # Yellow / orange / gray would paper over real failures.
    local script="$GOODIES_ROOT/modules/claude/scripts/tampermonkey/copilot-request-review.user.js"
    ! grep -qE "setTabStatus\([\"']yellow[\"']" "$script"
    ! grep -qE "setTabStatus\([\"']orange[\"']" "$script"
    ! grep -qE "setTabStatus\([\"']gray[\"']" "$script"
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

@test "env.sh exports GOODIES_SCRIPTS pointing to modules/claude/scripts" {
    run bash -c "source \"$GOODIES_ROOT/modules/claude/env.sh\"; echo \"\$GOODIES_SCRIPTS\""
    assert_success
    assert_output "$GOODIES_ROOT/modules/claude/scripts"
}

@test "goodies-watch-poll.sh exists and is executable" {
    [ -x "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" ]
}

@test "goodies-watch-poll.sh passes bash syntax check" {
    run bash -n "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh"
    assert_success
}

@test "goodies-watch-poll.sh exits 3 with usage when called with no args" {
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh"
    assert_failure 3
    assert_output --partial "Usage:"
}

# ---------------------------------------------------------------------------
# goodies-watch-poll.sh behaviour tests (mock gh)
# The mock gh: returns raw JSON per endpoint, then applies --jq filter via
# real jq so the script gets correctly filtered output.
# ---------------------------------------------------------------------------

# Write a mock gh that reads raw JSON from env vars per endpoint pattern,
# applies any --jq filter via real jq, and handles PATCH/POST/--include.
_write_mock_gh() {
    local mock_bin="$TEST_HOME/mock-bin"
    mkdir -p "$mock_bin"
    # Set defaults for all env vars before writing the mock, so the mock
    # itself never needs ${VAR:-json-with-braces} expansions (which break
    # because the closing } in the JSON terminates the parameter expansion).
    export GH_MOCK_PR="${GH_MOCK_PR:-}"
    export GH_MOCK_REQUESTED_REVIEWERS="${GH_MOCK_REQUESTED_REVIEWERS:-}"
    export GH_MOCK_REVIEWS="${GH_MOCK_REVIEWS:-[]}"
    export GH_MOCK_COMMENTS="${GH_MOCK_COMMENTS:-[]}"
    export GH_MOCK_GRAPHQL="${GH_MOCK_GRAPHQL:-}"
    export GH_MOCK_LAST_PUSH="${GH_MOCK_LAST_PUSH:-}"
    export GH_MOCK_NOW_HEADER="${GH_MOCK_NOW_HEADER:-Mon, 01 Jan 2024 04:00:00 GMT}"
    export GH_MOCK_REVIEW_POST_RESPONSE="${GH_MOCK_REVIEW_POST_RESPONSE:-}"
    export GH_MOCK_REVIEW_POST_EXIT="${GH_MOCK_REVIEW_POST_EXIT:-1}"

    cat > "$mock_bin/gh" <<'ENDMOCK'
#!/bin/bash
# Extract --jq filter if present (consuming --jq and its argument)
jq_filter=""
newargs=()
i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    if [[ "$arg" == "--jq" ]]; then
        i=$((i+1))
        jq_filter="${!i}"
    else
        newargs+=("$arg")
    fi
    i=$((i+1))
done

emit() {
    if [[ -n "$jq_filter" ]]; then
        printf '%s' "$1" | jq -r "$jq_filter"
    else
        printf '%s\n' "$1"
    fi
}

all_args="${newargs[*]:-}"

# Resolve defaults that couldn't safely be in ${VAR:-json} form
_pr="${GH_MOCK_PR}"
[[ -z "$_pr" ]] && _pr='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
_rr="${GH_MOCK_REQUESTED_REVIEWERS}"
[[ -z "$_rr" ]] && _rr='{"users":[],"teams":[]}'
_gql="${GH_MOCK_GRAPHQL}"
[[ -z "$_gql" ]] && _gql='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'

case "$all_args" in
    *"--include"*)
        printf 'date: %s\n\n' "$GH_MOCK_NOW_HEADER" ;;
    *"--method PATCH"*|*"-X PATCH"*)
        exit 0 ;;
    *"requested_reviewers"*"-X POST"*)
        printf '%s\n' "$GH_MOCK_REVIEW_POST_RESPONSE"
        exit "$GH_MOCK_REVIEW_POST_EXIT" ;;
    *"requested_reviewers"*)
        emit "$_rr" ;;
    *"graphql"*"pushedDate"*)
        # get_last_push_date query — return pushedDate+committedDate structure
        # GH_MOCK_PUSH_DATE_NULL=1 simulates pushedDate=null (fallback to committedDate)
        if [[ "${GH_MOCK_PUSH_DATE_NULL:-}" == "1" ]]; then
            _committed="${GH_MOCK_LAST_PUSH:-2024-01-01T00:00:00Z}"
            printf '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"pushedDate":null,"committedDate":"%s"}}]}}}}}\n' "$_committed"
        else
            _push_date="${GH_MOCK_LAST_PUSH:-2024-01-01T00:00:00Z}"
            printf '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"pushedDate":"%s","committedDate":"%s"}}]}}}}}\n' "$_push_date" "$_push_date"
        fi ;;
    *"graphql"*)
        emit "$_gql" ;;
    *"reviews"*)
        emit "$GH_MOCK_REVIEWS" ;;
    *"events"*)
        if [[ -n "$GH_MOCK_LAST_PUSH" ]]; then
            emit "[{\"type\":\"PushEvent\",\"payload\":{\"ref\":\"refs/heads/feat/test\"},\"created_at\":\"$GH_MOCK_LAST_PUSH\"}]"
        else
            emit "[]"
        fi ;;
    *"comments"*)
        emit "$GH_MOCK_COMMENTS" ;;
    *"assignees"*)
        emit "[]" ;;
    *"pulls/"*)
        emit "$_pr" ;;
    *)
        emit "[]" ;;
esac
ENDMOCK
    chmod +x "$mock_bin/gh"
    export PATH="$mock_bin:$PATH"
}

@test "poll script exits 3 when PR is closed" {
    _write_mock_gh
    export GH_MOCK_PR='{"state":"closed","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0001"
    assert_failure 3
    assert_output --partial "PR is closed"
}

@test "poll script exits 0 silently when Copilot review is pending" {
    _write_mock_gh
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[{"login":"copilot-pull-request-reviewer[bot]"}],"teams":[]}'
    export GH_MOCK_REVIEWS='[]'
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0002"
    assert_success
    refute_output
}

@test "poll script exits 2 (LGTM) when review is current with no inline comments" {
    _write_mock_gh
    # Push at 00:00, review at 00:30 (review AFTER push — current), no inline comments
    # → review is current, CMT_COUNT_LATEST=0 → LGTM
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    export GH_MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"submitted_at":"2024-01-01T00:30:00Z","state":"APPROVED"}]'
    export GH_MOCK_LAST_PUSH="2024-01-01T00:00:00Z"
    export GH_MOCK_COMMENTS='[]'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0003"
    assert_failure 2
    refute_output
}

@test "poll script exits 1 with findings when review is current with open threads" {
    _write_mock_gh
    # Push at 00:00, review at 00:30 (review current), has inline comment, thread unresolved
    # → falls through to Steps 1-3 → unreplied comment → exit 1 with findings JSON
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    # Review id=999; comment pull_request_review_id=999 so exact-ID matching is exercised
    export GH_MOCK_REVIEWS='[{"id":999,"user":{"login":"copilot-pull-request-reviewer[bot]"},"submitted_at":"2024-01-01T00:30:00Z","state":"CHANGES_REQUESTED"}]'
    export GH_MOCK_LAST_PUSH="2024-01-01T00:00:00Z"
    export GH_MOCK_COMMENTS='[{"id":101,"pull_request_review_id":999,"user":{"login":"copilot-pull-request-reviewer[bot]"},"in_reply_to_id":null,"path":"foo.sh","line":10,"body":"Fix this","created_at":"2024-01-01T00:31:00Z"}]'
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"}}]}}]}}}}}'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0003b"
    assert_failure 1
    assert_output --partial '"action":"findings"'
    assert_output --partial '"comments"'
}

@test "poll script exits 0 when API fails but marker is fresh (keep polling)" {
    _write_mock_gh
    # All threads resolved (OPEN_THREADS=0), API fails, no existing marker yet
    # → posts fresh marker and exits 0
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    export GH_MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"submitted_at":"2024-01-01T00:30:00Z","state":"CHANGES_REQUESTED"}]'
    export GH_MOCK_LAST_PUSH="2024-01-01T01:00:00Z"
    export GH_MOCK_COMMENTS='[{"id":101,"user":{"login":"copilot-pull-request-reviewer[bot]"},"in_reply_to_id":null,"path":"foo.sh","line":10,"body":"Fix this","created_at":"2024-01-01T00:31:00Z"}]'
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    export GH_MOCK_REVIEW_POST_RESPONSE='{"message":"Forbidden"}'
    export GH_MOCK_REVIEW_POST_EXIT=1
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0004"
    assert_success
    refute_output
}

@test "poll script exits 1 with timeout_fallback when own marker has expired" {
    _write_mock_gh
    # All threads resolved (OPEN_THREADS=0), API fails, PR body has OUR expired marker
    # → post_or_refresh_marker detects expired → exits 1 with timeout_fallback
    local expired_body
    expired_body='some pr text

<details><summary>goodies-watch handshake (writer=w-test-0005)</summary>

goodies-watch:click-request-review nonce=aabbccdd expires=2024-01-01T00:10:00Z writer=w-test-0005
</details>'
    export GH_MOCK_PR="{\"state\":\"open\",\"head\":{\"ref\":\"feat/test\"},\"created_at\":\"2024-01-01T00:00:00Z\",\"body\":$(printf '%s' "$expired_body" | jq -Rs .)}"
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    export GH_MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"submitted_at":"2024-01-01T00:30:00Z","state":"CHANGES_REQUESTED"}]'
    export GH_MOCK_LAST_PUSH="2024-01-01T01:00:00Z"
    export GH_MOCK_COMMENTS='[{"id":101,"user":{"login":"copilot-pull-request-reviewer[bot]"},"in_reply_to_id":null,"path":"foo.sh","line":10,"body":"Fix this","created_at":"2024-01-01T00:31:00Z"}]'
    # All threads resolved → OPEN_THREADS=0 → NEED_REQUEST=true → Step 0h
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    export GH_MOCK_REVIEW_POST_RESPONSE='{"message":"Forbidden"}'
    export GH_MOCK_REVIEW_POST_EXIT=1
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0005"
    assert_failure 1
    assert_output --partial '"action":"timeout_fallback"'
}

@test "poll script exits 0 when API review request succeeds (no marker posted)" {
    _write_mock_gh
    # No pending reviewer, but Copilot has a prior review (COPILOT_EVER=true).
    # Push is newer than last review → NEED_REQUEST=true → Step 0h fires.
    # API POST returns success (Copilot now pending) → exit 0 without posting a marker.
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    export GH_MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"submitted_at":"2024-01-01T00:30:00Z","state":"CHANGES_REQUESTED"}]'
    export GH_MOCK_LAST_PUSH="2024-01-01T01:00:00Z"
    export GH_MOCK_COMMENTS='[{"id":101,"user":{"login":"copilot-pull-request-reviewer[bot]"},"in_reply_to_id":null,"path":"foo.sh","line":10,"body":"Fix this","created_at":"2024-01-01T00:31:00Z"}]'
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    # POST returns reviewers list with Copilot — request_copilot_review succeeds
    export GH_MOCK_REVIEW_POST_RESPONSE='{"requested_reviewers":[{"login":"copilot-pull-request-reviewer[bot]"}]}'
    export GH_MOCK_REVIEW_POST_EXIT=0
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0006"
    assert_success
    refute_output
}

@test "poll script uses committedDate when pushedDate is null" {
    _write_mock_gh
    # Simulate a repo where pushedDate=null but committedDate is set (e.g. web-editor commits).
    # The commit timestamp predates the last review → push is NOT newer → check review content.
    # Review has an unreplied comment with an open thread → exit 1 with findings.
    export GH_MOCK_PR='{"state":"open","head":{"ref":"feat/test"},"created_at":"2024-01-01T00:00:00Z","body":""}'
    export GH_MOCK_REQUESTED_REVIEWERS='{"users":[],"teams":[]}'
    export GH_MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"id":9001,"submitted_at":"2024-01-01T01:00:00Z","state":"CHANGES_REQUESTED"}]'
    # pushedDate=null → script must fall back to committedDate (2024-01-01T00:30:00Z)
    # committedDate < last review (01:00:00) → push is NOT newer than review → continue to Step 0f
    export GH_MOCK_PUSH_DATE_NULL=1
    export GH_MOCK_LAST_PUSH="2024-01-01T00:30:00Z"
    export GH_MOCK_COMMENTS='[{"id":201,"pull_request_review_id":9001,"user":{"login":"copilot-pull-request-reviewer[bot]"},"in_reply_to_id":null,"path":"foo.sh","line":5,"body":"Use quotes","created_at":"2024-01-01T01:00:00Z"}]'
    export GH_MOCK_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"}}]}}]}}}}}'
    export GH_MOCK_NOW_HEADER="Mon, 01 Jan 2024 04:00:00 GMT"
    run bash "$GOODIES_ROOT/modules/claude/scripts/goodies-watch-poll.sh" \
        "owner/repo" "42" "w-test-0007"
    assert_failure 1
    assert_output --partial '"action":"findings"'
    assert_output --partial '"id":201'
}
