---
allowed-tools: Bash, Read, Write, Edit, Agent
---

Scan recent Claude session transcripts and identify solutions worth extracting into portable, shareable tools or documentation.

## Arguments

- No argument: scan since last run (or last 7 days if never run before)
- `-N` (e.g., `-7`, `-30`): scan sessions modified within the last N days

## Steps

1. Determine the time range:
   - Check `~/.claude/.distill_last_run` for the timestamp of the last run
   - If the user passed `-N`, use that as the day range (find uses `-mtime -N`, meaning "modified within the last N days")
   - If no argument and no last-run file, default to 7 days
   - If no argument but last-run exists, use days since last run (minimum 1)

2. Find all session transcripts across all projects:
   ```
   find ~/.claude/projects -name '*.jsonl' -mtime -<DAYS>
   ```

3. For each transcript, extract what was built by parsing assistant tool_use blocks (files written, significant commands run):

   ```bash
   python3 -c "
   import sys, json
   for line in open(sys.argv[1]):
       try:
           obj = json.loads(line)
       except (json.JSONDecodeError, ValueError):
           continue
       if obj.get('type') == 'assistant':
           msg = obj.get('message', {})
           content = msg.get('content', [])
           if isinstance(content, list):
               for block in content:
                   if not isinstance(block, dict) or block.get('type') != 'tool_use':
                       continue
                   inputs = block.get('input', {})
                   if block.get('name') == 'Write':
                       print(f\"WROTE: {inputs.get('file_path', '')}\")
                   elif block.get('name') == 'Bash':
                       cmd = inputs.get('command', '')
                       if len(cmd) > 20:
                           print(f\"RAN: {cmd[:150]}\")
   " <transcript_path>
   ```

4. Present a digest to the user:

   ```
   ## Session Digest (last N days)

   ### <Project Name>
   **Session:** <date> — <one-line summary of what was built>
   **Portable candidates:**
   - <script/tool/pattern> — <why it's reusable>

   ### <Project Name>
   ...
   ```

5. For each candidate, ask the user: "Want me to extract this into a standalone tool/README?"

6. If the user says yes for any candidate:
   - Determine the appropriate module (existing or new)
   - Extract the solution into a clean, documented script or config
   - Update the module's install.sh if needed
   - Create a PR following the standard workflow

7. After completing the digest, update the last-run timestamp:
   ```
   date -Iseconds > ~/.claude/.distill_last_run
   ```

## Guidelines

- Skip sessions that only did project-specific work (bug fixes, feature implementation) with no reusable patterns
- Focus on solutions to problems that other engineers would encounter
- Look for patterns like: "I had to do X every time, so I automated it" or "this workaround fixes Y"
- Don't include sensitive data (tokens, internal URLs, credentials) in extracted solutions
- Prefer extracting into existing modules when the solution fits (e.g., shell functions → bash module, git workflows → git module)
