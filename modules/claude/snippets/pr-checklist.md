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
