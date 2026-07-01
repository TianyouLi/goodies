#!/bin/bash
# goodies-watch-poll.sh <REPO> <PR> <WATCHER_ID>
#
# Deterministic Copilot review polling logic, extracted from goodies-watch.md.
# Exit codes:
#   0 — nothing actionable; keep polling silently
#   1 — actionable event; one JSON line written to stdout
#   2 — LGTM (no unreplied comments, review is fresh); stdout empty
#   3 — fatal (PR closed/merged, access error); error string on stdout

set -euo pipefail

REPO="${1:-}"
PR="${2:-}"
WATCHER_ID="${3:-}"

if [[ -z "$REPO" || -z "$PR" || -z "$WATCHER_ID" ]]; then
    echo "Usage: goodies-watch-poll.sh <REPO> <PR> <WATCHER_ID>"
    exit 3
fi
# Validate inputs early to prevent code injection in embedded Python snippets
if ! [[ "$PR" =~ ^[0-9]+$ ]]; then
    echo "Invalid PR number: $PR"
    exit 3
fi
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid REPO format (expected owner/repo): $REPO"
    exit 3
fi
if ! [[ "$WATCHER_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Invalid WATCHER_ID (alphanumeric, hyphens, underscores only): $WATCHER_ID"
    exit 3
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Return the push time of the most recent commit on this PR via GraphQL.
# Prefers pushedDate (set when pushed via git); falls back to committedDate
# (always set). Both are more reliable than the Events API.
# Outputs ISO-8601 UTC timestamp, or empty string on API failure.
get_last_push_date() {
    local owner="${REPO%%/*}" repo_name="${REPO##*/}"
    python3 -c "
import subprocess, json, sys
r = subprocess.run(
    ['gh', 'api', 'graphql', '-f',
     'query={ repository(owner: \"$owner\", name: \"$repo_name\") { pullRequest(number: $PR) { commits(last:1) { nodes { commit { pushedDate committedDate } } } } } }'],
    capture_output=True, text=True)
if r.returncode != 0:
    sys.exit(0)
try:
    d = json.loads(r.stdout)
    c = d['data']['repository']['pullRequest']['commits']['nodes'][0]['commit']
    date = c.get('pushedDate') or c.get('committedDate') or ''
    print(date, end='')
except Exception:
    sys.exit(0)
" 2>/dev/null || true
}

gh_now() {
    local raw
    raw=$(gh api "repos/$REPO" --include 2>/dev/null | grep -i '^date:' | sed 's/^[Dd]ate: //' || true)
    if [[ -n "$raw" ]]; then
        RAW_DATE="$raw" python3 -c "
import os, email.utils, datetime
d = email.utils.parsedate_to_datetime(os.environ['RAW_DATE'])
print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null && return
    fi
    # Fallback to local clock — acceptable for staleness checks; no external dependency
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

strip_own_marker() {
    local old_body
    old_body=$(gh api "repos/$REPO/pulls/$PR" --jq .body 2>/dev/null) || return 0
    local new_body
    new_body=$(printf '%s' "$old_body" | WATCHER_ID="$WATCHER_ID" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
pat = (r"\n*<details><summary>goodies-watch[^<]*</summary>"
       r"\s*goodies-watch:click-request-review nonce=\S+ expires=\S+ writer=" + wid +
       r"\s*</details>\n*")
b = re.sub(pat, "\n", b, flags=re.DOTALL)
sys.stdout.write(b)
') || return 0
    if [[ "$old_body" != "$new_body" ]]; then
        gh api --method PATCH "/repos/$REPO/pulls/$PR" -f body="$new_body" >/dev/null 2>&1 || true
    fi
}

# Discover Copilot's reviewer login dynamically.
# Sets global COPILOT_LOGIN.
discover_copilot_login() {
    COPILOT_LOGIN=$(gh api "repos/$REPO/pulls/$PR/requested_reviewers" \
        --jq '.users[].login' 2>/dev/null | grep -i 'copilot' | head -1 || true)
    if [[ -z "$COPILOT_LOGIN" ]]; then
        COPILOT_LOGIN=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
            --jq '.[].user.login' 2>/dev/null | grep -i 'copilot' | head -1 || true)
    fi
    if [[ -z "$COPILOT_LOGIN" ]]; then
        COPILOT_LOGIN=$(gh api --paginate "repos/$REPO/assignees" \
            --jq '.[].login' 2>/dev/null | grep -i 'copilot' | head -1 || true)
    fi
    if [[ -z "$COPILOT_LOGIN" ]]; then
        COPILOT_LOGIN="copilot-pull-request-reviewer[bot]"
    fi
}

# Attempt to request Copilot review via the GitHub API.
# Returns 0 on success, 1 on failure.
# On failure, sets global REVIEW_REQUEST_ERR to the captured error output.
REVIEW_REQUEST_ERR=""
request_copilot_review() {
    discover_copilot_login
    local api_response api_exit
    if api_response=$(gh api "repos/$REPO/pulls/$PR/requested_reviewers" \
        -X POST -f "reviewers[]=$COPILOT_LOGIN" 2>&1); then
        api_exit=0
    else
        api_exit=$?
    fi
    local api_success
    api_success=$(printf '%s' "$api_response" | jq -r \
        '[.requested_reviewers[]?.login | test("copilot";"i")] | any' 2>/dev/null || echo "false")
    if [[ "$api_exit" -eq 0 && "$api_success" == "true" ]]; then
        REVIEW_REQUEST_ERR=""
        return 0
    fi
    REVIEW_REQUEST_ERR="$api_response"
    return 1
}

# Post the Tampermonkey click-request-review marker in the PR body (written once).
# If a valid unexpired marker already exists: returns 0 without updating it.
# If the existing marker has expired (or is malformed): exits 1 with {"action":"timeout_fallback"}.
# If no marker exists yet: writes a new one with a fixed expires (now+600s) and returns 0.
post_or_refresh_marker() {
    local old_body
    old_body=$(gh api "repos/$REPO/pulls/$PR" --jq .body 2>/dev/null) || {
        # Transient API failure — can't read PR body, keep polling silently
        exit 0
    }
    [[ "$old_body" == "null" || -z "$old_body" ]] && old_body=""

    # Check if our existing marker has expired — extract expires scoped to our own block
    local existing_expires
    existing_expires=$(printf '%s' "$old_body" | WATCHER_ID="$WATCHER_ID" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
m = re.search(
    r"<details><summary>goodies-watch[^<]*</summary>"
    r"\s*goodies-watch:click-request-review nonce=\S+ expires=(\S+) writer=" + wid,
    b, re.DOTALL)
print(m.group(1) if m else "")
' || true)

    if [[ -n "$existing_expires" ]]; then
        local gh_now_val marker_expired
        gh_now_val=$(gh_now)
        marker_expired=$(jq -rn \
            --arg now "$gh_now_val" \
            --arg exp "$existing_expires" \
            '($now | fromdateiso8601) >= ($exp | fromdateiso8601)' 2>/dev/null || echo "true")
        if [[ "$marker_expired" == "true" ]]; then
            printf '{"action":"timeout_fallback"}\n'
            exit 1
        fi
        # Marker exists and has not expired — don't extend expires, just keep polling
        return 0
    fi

    local gh_now_val nonce expires marker_payload marker_block new_body
    gh_now_val=$(gh_now)
    nonce=$(openssl rand -hex 4 2>/dev/null || python3 -c "import os; print(os.urandom(4).hex())")
    expires=$(jq -rn --arg now "$gh_now_val" '($now | fromdateiso8601) + 600 | todateiso8601')

    marker_payload="goodies-watch:click-request-review nonce=$nonce expires=$expires writer=$WATCHER_ID"
    marker_block=$(printf '<details><summary>goodies-watch handshake (writer=%s)</summary>\n\n%s\n</details>' \
        "$WATCHER_ID" "$marker_payload")

    new_body=$(printf '%s' "$old_body" | WATCHER_ID="$WATCHER_ID" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
pat = (r"\n*<details><summary>goodies-watch[^<]*</summary>"
       r"\s*goodies-watch:click-request-review nonce=\S+ expires=\S+ writer=" + wid +
       r"\s*</details>\n*")
b = re.sub(pat, "\n", b, flags=re.DOTALL)
sys.stdout.write(b)
')
    new_body=$(printf '%s\n\n%s\n' "$new_body" "$marker_block")
    local patch_err patch_exit
    patch_err=$(gh api --method PATCH "/repos/$REPO/pulls/$PR" -f body="$new_body" 2>&1) || patch_exit=$?
    patch_exit="${patch_exit:-0}"
    if [[ "$patch_exit" -ne 0 ]]; then
        if printf '%s' "$patch_err" | grep -qiE 'not found|401|403|404'; then
            echo "Cannot post review-request marker — no permission to edit PR body: $patch_err"
            exit 3
        fi
        # Transient (network, rate limit) — keep polling silently
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Step 0a: PR state
# ---------------------------------------------------------------------------
STATE_ERR=$(mktemp /tmp/goodies-watch-XXXXXX)
STATE=$(gh api "repos/$REPO/pulls/$PR" --jq .state 2>"$STATE_ERR") || {
    _err=$(<"$STATE_ERR"); rm -f "$STATE_ERR"
    # 401/404/not-found: permanent access failure
    if echo "$_err" | grep -qiE 'not found|401|404'; then
        echo "Failed to fetch PR state: $_err"
        exit 3
    fi
    # 403: rate-limit (contains "rate limit") → transient; other 403/forbidden → permanent
    if echo "$_err" | grep -qiE 'forbidden|403'; then
        if echo "$_err" | grep -qiE 'rate.?limit|secondary'; then
            exit 0  # transient rate limit, keep polling
        fi
        echo "Failed to fetch PR state (permission/policy error): $_err"
        exit 3
    fi
    exit 0  # other transient errors (TLS, DNS, network)
}
rm -f "$STATE_ERR"
if [[ "$STATE" != "open" ]]; then
    strip_own_marker 2>/dev/null || true
    echo "PR is $STATE"
    exit 3
fi

# ---------------------------------------------------------------------------
# Step 0b: Has Copilot ever been involved?
# ---------------------------------------------------------------------------
if ! COPILOT_REVIEWER=$(gh api "repos/$REPO/pulls/$PR/requested_reviewers" \
    --jq '[.users[].login | test("copilot"; "i")] | any' 2>/dev/null); then
    exit 0  # transient failure — keep polling
fi
COPILOT_EVER_COUNT=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
    --jq '[.[] | select(.user.login | test("copilot";"i"))] | length' \
    2>/dev/null | awk '{s+=$1} END{print s+0}') || exit 0
COPILOT_EVER=$([ "${COPILOT_EVER_COUNT:-0}" -gt 0 ] && echo true || echo false)

NEED_REQUEST=false

if [[ "$COPILOT_REVIEWER" != "true" && "$COPILOT_EVER" != "true" ]]; then
    # Fresh PR — no history at all, request initial review
    NEED_REQUEST=true
elif [[ "$COPILOT_REVIEWER" == "true" ]]; then
    # Step 0c: review currently pending — nothing to do
    strip_own_marker 2>/dev/null || true
    exit 0
else
    # Copilot has reviewed before and is not currently pending
    COUNT_SUBMITTED=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
        --jq '[.[] | select(.user.login | test("copilot";"i")) | select(.submitted_at != null)] | length' \
        2>/dev/null | awk '{s+=$1} END{print s+0}') || exit 0

    if [[ "$COUNT_SUBMITTED" -eq 0 ]]; then
        NEED_REQUEST=true
    else
        # Step 0e: compare LAST_PUSH vs LAST_REVIEW
        LAST_COMMENT=$(gh api --paginate "repos/$REPO/pulls/$PR/comments" \
            --jq '.[] | select(.user.login | test("copilot";"i")) | select(.in_reply_to_id == null) | .created_at' \
            2>/dev/null | sort | tail -n 1 || true)
        LAST_REVIEW_SUBMITTED=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
            --jq '.[] | select(.user.login | test("copilot";"i")) | select(.submitted_at != null) | .submitted_at' \
            2>/dev/null | sort | tail -n 1 || true)
        LAST_REVIEW=$(jq -rn \
            --arg c "${LAST_COMMENT:-1970-01-01T00:00:00Z}" \
            --arg r "${LAST_REVIEW_SUBMITTED:-1970-01-01T00:00:00Z}" \
            '[($c | fromdateiso8601), ($r | fromdateiso8601)] | max | todateiso8601')

        LAST_PUSH=$(get_last_push_date)
        if [[ -z "$LAST_PUSH" ]]; then
            exit 0  # transient — can't determine push time; keep polling
        fi

        PUSH_AFTER_REVIEW=$(echo "$LAST_PUSH $LAST_REVIEW" | jq -R \
            'split(" ") | (.[0] | fromdateiso8601) > (.[1] | fromdateiso8601)')

        if [[ "$PUSH_AFTER_REVIEW" == "true" ]]; then
            # Push is newer than last review — review is stale, need a fresh one
            NEED_REQUEST=true
        else
            # Review is current (covers latest push) — check its content

            # Step 0f: Did last review have inline comments?
            # Use the review ID for exact matching — time windows cause false positives
            # when old comments from a prior cycle fall within ±1h of the latest review.
            LAST_REVIEW=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
                --jq '.[] | select(.user.login | test("copilot";"i")) | select(.submitted_at != null) | {id, submitted_at, state}' \
                2>/dev/null | jq -rs 'sort_by(.submitted_at) | last') || exit 0
            LAST_REVIEW_ID=$(printf '%s' "$LAST_REVIEW" | jq -r '.id')
            LAST_REVIEW_STATE=$(printf '%s' "$LAST_REVIEW" | jq -r '.state')
            CMT_COUNT_LATEST=$(gh api --paginate "repos/$REPO/pulls/$PR/comments" \
                --jq '[.[] | select(.user.login | test("copilot";"i")) | select(.in_reply_to_id == null) | .pull_request_review_id]' \
                2>/dev/null | jq -s --argjson rid "$LAST_REVIEW_ID" '[.[] | .[] | select(. == $rid)] | length') || exit 0

            if [[ "$CMT_COUNT_LATEST" -eq 0 ]]; then
                if [[ "$LAST_REVIEW_STATE" == "APPROVED" ]]; then
                    # Last review was approval with no inline comments — LGTM
                    strip_own_marker 2>/dev/null || true
                    exit 2
                else
                    # Summary-only non-approval (e.g. CHANGES_REQUESTED) — surface as actionable
                    printf '{"action":"findings","comments":[],"review_state":"%s"}\n' "$LAST_REVIEW_STATE"
                    exit 1
                fi
            fi

            # Step 0g: Are all Copilot threads resolved or outdated? (paginated)
            OWNER="${REPO%%/*}"
            REPO_NAME="${REPO##*/}"
            OPEN_THREADS=$(python3 -c "
import subprocess, json, sys

owner, repo_name, pr = '$OWNER', '$REPO_NAME', $PR
cursor = 'null'
total = 0
while True:
    after = f', after: \"{cursor}\"' if cursor != 'null' else ''
    query = '''{ repository(owner: \"%s\", name: \"%s\") {
        pullRequest(number: %d) {
            reviewThreads(first: 100 %s) {
                pageInfo { hasNextPage endCursor }
                nodes {
                    isResolved isOutdated
                    comments(first: 1) { nodes { author { login } } }
                }
            }
        }
    }}''' % (owner, repo_name, pr, after)
    r = subprocess.run(['gh', 'api', 'graphql', '-f', 'query=' + query],
                       capture_output=True, text=True)
    if r.returncode != 0:
        # API failure — treat as unknown (may have open threads); keep polling
        print('error'); sys.exit(0)
    try:
        data = json.loads(r.stdout)
        if 'errors' in data or not data.get('data'):
            print('error'); sys.exit(0)
        threads = data['data']['repository']['pullRequest']['reviewThreads']
    except (KeyError, TypeError, ValueError):
        print('error'); sys.exit(0)
    for n in threads['nodes']:
        if not n['isResolved'] and not n['isOutdated']:
            login = (n['comments']['nodes'] or [{}])[0].get('author', {}).get('login', '')
            if 'copilot' in login.lower():
                total += 1
    if not threads['pageInfo']['hasNextPage']:
        break
    cursor = threads['pageInfo']['endCursor']
print(total)
")

            if [[ "$OPEN_THREADS" == "error" ]]; then
                # GraphQL API failure — unknown state, keep polling silently
                exit 0
            elif [[ "$OPEN_THREADS" -gt 0 ]]; then
                # There are unaddressed Copilot threads — fall through to Steps 1-3
                : # no-op
            else
                # All threads resolved — request a fresh review
                NEED_REQUEST=true
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Step 0h: Request review (API-first, userscript fallback)
# Only fires if Step 0b–0g determined a request is needed.
# On API success: exit 0 (Copilot is now pending; next poll will see it).
# On API failure: post Tampermonkey marker, then exit 0 to keep polling —
#   unless the marker has expired, in which case post_or_refresh_marker
#   exits 1 with {"action":"timeout_fallback"} before we reach the exit 0.
# ---------------------------------------------------------------------------
if [[ "$NEED_REQUEST" == "true" ]]; then
    if ! request_copilot_review; then
        # API failed — post/refresh Tampermonkey marker
        # post_or_refresh_marker exits 1 with timeout_fallback if marker expired
        post_or_refresh_marker
        exit 0
    fi
    # API succeeded — Copilot is now pending; exit 0 and let the next poll confirm
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Is review currently pending?
# ---------------------------------------------------------------------------
PENDING=$(gh api "repos/$REPO/pulls/$PR/requested_reviewers" \
    --jq '[.users[].login | test("copilot";"i")] | any' 2>/dev/null) || exit 0
if [[ "$PENDING" == "true" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: Find unreplied Copilot inline comments
# ---------------------------------------------------------------------------
COPILOT_TOP_IDS=$(gh api --paginate "repos/$REPO/pulls/$PR/comments" \
    --jq '[.[] | select(.user.login | test("copilot";"i")) | select(.in_reply_to_id == null) | .id]' \
    2>/dev/null | jq -s 'add // []') || exit 0
REPLY_TARGET_IDS=$(gh api --paginate "repos/$REPO/pulls/$PR/comments" \
    --jq '[.[] | .in_reply_to_id] | map(select(. != null))' \
    2>/dev/null | jq -s 'add // []') || exit 0

UNREPLIED_COUNT=$(jq -rn \
    --argjson top "$COPILOT_TOP_IDS" \
    --argjson replied "$REPLY_TARGET_IDS" \
    '[$top[] | select(. as $id | $replied | index($id) == null)] | length')

# ---------------------------------------------------------------------------
# Step 3: Staleness + outcome decision
# ---------------------------------------------------------------------------
COUNT_SUBMITTED=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
    --jq '[.[] | select(.user.login | test("copilot";"i")) | select(.submitted_at != null)] | length' \
    2>/dev/null | awk '{s+=$1} END{print s+0}') || exit 0

if [[ "$COUNT_SUBMITTED" -eq 0 ]]; then
    if request_copilot_review; then
        exit 0
    else
        # Classify the failure using the error captured by request_copilot_review
        # (no second POST needed — avoids triggering duplicate review requests)
        if printf '%s' "$REVIEW_REQUEST_ERR" | grep -qiE 'not found|401|404'; then
            echo "Could not request Copilot review — no access. Ask a repo maintainer to request review manually."
            exit 3
        fi
        # 403/transient — use marker fallback so Tampermonkey can trigger review
        post_or_refresh_marker
        exit 0
    fi
fi

# Compute push age using GitHub server clock
LAST_PUSH=$(get_last_push_date)
if [[ -z "$LAST_PUSH" ]]; then
    exit 0  # transient — can't determine push time; keep polling
fi

GH_NOW_VAL=$(gh_now)
PUSH_AGE=$(jq -rn \
    --arg push "$LAST_PUSH" \
    --arg now "$GH_NOW_VAL" \
    '(($now | fromdateiso8601) - ($push | fromdateiso8601)) | floor')

if (( PUSH_AGE < 180 )) && [[ "$UNREPLIED_COUNT" -eq 0 ]]; then
    exit 0
fi

if [[ "$UNREPLIED_COUNT" -gt 0 ]]; then
    # Fetch full details for unreplied comments
    FINDINGS=$(jq -rn \
        --argjson top "$COPILOT_TOP_IDS" \
        --argjson replied "$REPLY_TARGET_IDS" \
        '[$top[] | select(. as $id | $replied | index($id) == null)]' \
    )
    FINDINGS_DETAILS=$(gh api --paginate "repos/$REPO/pulls/$PR/comments" \
        --jq "[.[] | select(.user.login | test(\"copilot\";\"i\")) | select(.in_reply_to_id == null) | {id, path, line, body}]" \
        2>/dev/null | jq -sc --argjson findings "$FINDINGS" \
            'add // [] | map(select(.id as $id | $findings | index($id) != null))') || exit 0
    printf '{"action":"findings","comments":%s}\n' "$FINDINGS_DETAILS"
    exit 1
fi

# No unreplied comments and review is fresh — check for approval
LAST_STATE=$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
    --jq '.[] | select(.user.login | test("copilot";"i")) | select(.submitted_at != null) | {submitted_at, state}' \
    2>/dev/null | jq -rs 'sort_by(.submitted_at) | last | .state') || exit 0
if [[ "$LAST_STATE" == "APPROVED" ]]; then
    strip_own_marker 2>/dev/null || true
    exit 2
else
    # Non-approval with no inline comments — surface as actionable
    printf '{"action":"findings","comments":[],"review_state":"%s"}\n' "$LAST_STATE"
    exit 1
fi
