# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles and tooling repository organized into self-contained modules. Each module has its own `install.sh` that symlinks configs and adds tools to PATH.

## Workflow

All changes must go through a feature branch + PR with Copilot review before merging to master. Never push directly to master. Use `/goodies-watch` to monitor Copilot review results and fix findings automatically. Only merge after `/goodies-watch` reports LGTM (all findings addressed).

## Repository Structure

- **install.sh** — Orchestrator that runs all module installers (or specific ones: `./install.sh git tmux`)
  - `--full` flag additionally runs `bootstrap.sh` for modules that have one (e.g., package installs, validation)
- **modules/** — Self-contained modules, each with `install.sh`
- **lib/goodies-lib.sh** — Shared helpers (safe_link, ensure_dir, path_append, logging, platform detection)
- **tests/** — BATS test suite with per-module and integration tests
- **.github/workflows/test.yml** — CI runs BATS on push/PR

## Modules

| Module | Purpose |
|--------|---------|
| bash | Shell aliases, bash_profile (macOS) |
| claude | Claude Code settings.json, custom commands |
| clickhouse | ClickHouse build/bench/launch scripts, SSB/ClickBench harnesses |
| emacs | .emacs config |
| git | Git config, clang-format, git_env |
| kernel | corescale.py (CPU scaling), kboot.sh (kexec) |
| packer | VM provisioning templates (Chromium dev, Ubuntu dev) |
| perf | pt.sh (perf record/report/c2c wrapper) |
| proxy | switchproxy.sh |
| tmux | .tmux.conf, TPM (git submodule) |

## Testing

```bash
# Run all tests
bash tests/run.sh

# Run a single module's tests
tests/bats/bats-core/bin/bats tests/modules/bash.bats

# Run integration tests
tests/bats/bats-core/bin/bats tests/integration.bats
```

BATS submodules (bats-core, bats-support, bats-assert) live under `tests/bats/`.

## Module Install Pattern

Each module's `install.sh` sources the shared library and uses `safe_link` / `path_append`:

```bash
#!/bin/bash
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"
safe_link "${BASEDIR}/config" ~/.config
```

`safe_link` skips if destination is a regular file (not a symlink) and returns non-zero in that case. Module installers end with `true` to avoid failing under `set -e` when a skip occurs.

Modules can optionally include a `bootstrap.sh` for heavier setup (package installs, validation, compilation). It only runs when `--full` is passed to the orchestrator.

## Key Tools

- `corescale.py` — CPU online/offline + cgroup-based core scaling for ClickHouse benchmarks (requires root)
- `kboot.sh` — kexec-based kernel switching from /boot
- `pt.sh <label> <command>` — Perf tracing with hotspot + c2c reports
- `ck_build.sh` / `ck_bench.sh` / `ck_launch.sh` — ClickHouse build and benchmark automation

## Branch Naming Convention

Branch names mirror commit types:

```
<type>/<short-description>
```

**Examples:**
- `feat/obi-installer`
- `fix/broken-symlinks`
- `docs/expand-claude-md`
- `ci/release-workflow`
- `refactor/rename-cli`
- `test/add-install-tests`

**Rules:**
- Use lowercase with hyphens (no underscores or camelCase)
- Keep descriptions short (2-4 words)
- Use the same type vocabulary as commits: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `perf`

## Commit Message Convention

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <short summary>

<optional body — explain WHY, not WHAT>
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `perf`

**Scope:** module or area affected (e.g., `install`, `ci`, `readme`). Omit if change is cross-cutting.

**Rules:**
- Subject line under 70 characters
- Imperative mood ("add", not "added" or "adds")
- Body explains motivation/trade-offs, not a restatement of the diff
- Breaking changes: add `!` after type/scope (e.g., `feat(api)!: remove v1 endpoint`)

## Copilot Review Workflow

All PRs require Copilot code review before merging.

**Process:**
1. Create PR and wait for Copilot review
2. For each finding: fix the issue, push, then reply with "Fixed in <sha>. <explanation>"
3. Only merge after all findings are addressed (LGTM)

**Rules:**
- Never dismiss a finding without explanation
- If a finding is invalid, reply explaining why (don't just ignore it)
- Squash fixup commits before merge when there are multiple rounds of review
- Use `/goodies-watch` to monitor for new reviews automatically
- If Copilot review is not triggering, check that the `copilot-ruleset` convention has been applied to this repo

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

## PR Checklist by Type

Before creating a PR, ensure the required artifacts are present based on the commit type:

| Type | Required Artifacts |
|------|-------------------|
| `feat` | Design doc (in `docs/design/` or linked in PR body) |
| `fix` | Test case that reproduces the bug (must fail without the fix) |
| `refactor` | Passing tests proving no behavior change |
| `test` | — |
| `ci` | — |
| `docs` | — |
| `perf` | Benchmark results (before/after) in PR body |

**Rules:**
- Block PR creation if required artifacts are missing — ask the user to provide them first
- Design docs can be brief (problem, approach, trade-offs) — a paragraph is fine for small features
- For `fix`, if no test framework exists yet, describe the manual reproduction steps in the PR body
- For `feat` that are trivial (< 20 lines, no new API surface), a design doc is not required — note "trivial feature" in the PR body instead

**CI enforcement:**
When the project is hosted on GitHub, suggest adding a GitHub Actions workflow (creating `.github/workflows/` if it doesn't exist) that:
- Validates PR title matches `type(scope): summary` format
- Checks commit messages follow the same convention
- Verifies required artifacts per type (e.g., `fix` PRs must include changes under `tests/`)
- Reports violations as PR check failures with clear error messages explaining what's missing

## Pull Request Convention

**Title:** Same format as commits — `type(scope): short summary` under 70 characters.

**Body structure:**
1. Lead with the problem/motivation (WHY this change exists)
2. Summary of what changed (bullet points, 1-3 lines)
3. Test plan if applicable

**Rules:**
- Title describes the outcome, not the activity ("add X" not "working on X")
- Body's first sentence is the problem statement, not a description of the diff
- Keep description useful for someone reviewing without prior context
- Link related issues/PRs if they exist
