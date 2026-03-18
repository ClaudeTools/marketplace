---
name: logs
description: Extract and query Claude Code session logs — /btw side-questions, conversation history, tool usage, errors, and search. Use when the user says logs, btw logs, session logs, show logs, side questions, conversation history, tool usage, error log, search sessions.
argument-hint: [subcommand] [args] — btw, search, tools, errors, conversation, summary
allowed-tools: Bash
context: none
metadata:
  author: Owen Innes
  version: 1.2.0
  category: meta
  tags: [logs, btw, sessions, search, tools, errors]
---

# Session Logs

Run the log extraction script and show the output directly.

## Workflow

1. Map the user's request to a `logs.sh` command:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/logs/scripts/logs.sh ${ARGUMENTS:-summary}
```

The script handles all parsing. Common patterns:
- `/logs btw` → last btw Q&A
- `/logs btw --last 5` → last 5 btw conversations
- `/logs btw --all --from today` → all btw from today
- `/logs search "term"` → search for a term
- `/logs tools` → tool usage per session
- `/logs errors` → errors and failures
- `/logs conversation` → latest full conversation
- `/logs summary` → session overview (default)

2. Show the output to the user as-is. If the output is very large (50+ lines), summarize the key points and offer to save the full output to a file.

3. If no data found, say: "No session data found. Logs appear in ~/.claude/projects/ after at least one session."

## Flags (all subcommands)

- `--last N` — limit results (btw defaults to 1, others to 10)
- `--all` — all projects
- `--session ID` — filter to session
- `--from VALUE` — date filter: today, yesterday, "N days ago", this week, YYYY-MM-DD
