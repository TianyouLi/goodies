## Copilot Review Ruleset

When setting up a new project or when asked to enable Copilot review, create a GitHub repository ruleset that triggers Copilot code review automatically on every push to PRs targeting the default branch.

**Setup command:**
```bash
gh api repos/<OWNER>/<REPO>/rulesets -X POST -H "Accept: application/vnd.github+json" --input - <<'EOF'
{
  "name": "Copilot review for default branch",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "copilot_code_review", "parameters": { "review_on_push": true, "review_draft_pull_requests": true } }
  ]
}
EOF
```

**Pre-checks before applying:**
1. Verify the repo is public (or owner has GitHub Pro/Team/Enterprise): `gh repo view <OWNER>/<REPO> --json visibility -q .visibility`
2. Check if a Copilot ruleset already exists: `gh api repos/<OWNER>/<REPO>/rulesets --jq '.[] | select(.name | test("copilot"; "i"))'`
3. If it already exists, report "Copilot review ruleset already configured" and skip

**Constraints:**
- Rulesets require the repo to be **public** or the owner to have **GitHub Pro/Team/Enterprise**
- Private repos on free plans will get HTTP 403
- The `~DEFAULT_BRANCH` target auto-adapts to whatever the repo's default branch is (main, master, etc.)
