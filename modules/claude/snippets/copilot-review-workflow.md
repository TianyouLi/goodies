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
