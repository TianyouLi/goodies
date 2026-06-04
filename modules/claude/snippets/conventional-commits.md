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
