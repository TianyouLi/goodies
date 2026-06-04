---
allowed-tools: Bash, Read, Edit, Write
---

Append convention snippets from the goodies library to the current project's CLAUDE.md.

## Arguments

- No argument: list available snippets
- `all`: append every available snippet
- Snippet name(s): append those snippets (e.g., `conventional-commits`)

## Steps

1. Resolve the snippets directory:
   ```
   SNIPPETS_DIR="$(cd ~/.claude/snippets 2>/dev/null && pwd -P || echo "")"
   ```
   If `SNIPPETS_DIR` is empty or does not exist, try:
   ```
   SNIPPETS_DIR="$HOME/goodies/modules/claude/snippets"
   ```
   If neither path is a valid directory, tell the user "No snippets directory found" and stop.

2. If no arguments were provided, list available snippets:
   ```
   ls "$SNIPPETS_DIR"/*.md | sed 's|.*/||; s|\.md$||'
   ```
   Print the list and stop.

3. If the argument is `all`, expand it to the full list of snippet names (same as step 2 listing).

4. For each requested snippet name:
   a. Check if `$SNIPPETS_DIR/<name>.md` exists. If not, report "Unknown snippet: <name>" and skip.
   b. Read the snippet file content.
   c. Find the project's CLAUDE.md — look for `./CLAUDE.md` in the current working directory. If it doesn't exist, create it with a `# CLAUDE.md` header.
   d. Check if the snippet's first heading (e.g., `## Commit Message Convention`) already appears in CLAUDE.md. If it does, report "Already present: <name>" and skip.
   e. Append a blank line + the snippet content to the end of CLAUDE.md.
   f. Report "Added: <name>"

5. After processing all snippets, show a short summary of what was added/skipped.
