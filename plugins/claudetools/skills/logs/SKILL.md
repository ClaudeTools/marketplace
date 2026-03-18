---
name: logs
description: Extract and query Claude Code session logs — /btw side-questions, conversation history, tool usage, errors, and search. Use when the user says logs, btw logs, session logs, show logs, side questions, conversation history, tool usage, error log, or search sessions.
argument-hint: [subcommand] [args] — btw, search, tools, errors, conversation, summary
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.0.0
  category: meta
  tags: [logs, btw, sessions, search, tools, errors]
---

# Session Logs

Extract and query Claude Code JSONL session logs.

## Workflow

1. Run the log extraction script with the user's arguments:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/logs/scripts/logs.sh ${ARGUMENTS:-summary}
```

2. Present the output to the user. Format markdown tables or structured output as appropriate for the subcommand.

3. If no sessions or data found, tell the user: "No session data found for the current project. Claude Code stores session logs in ~/.claude/projects/ — they appear after at least one session."

## Subcommands

- `summary` (default) — One-line overview per session: date, turns, tools, size, topic
- `btw [--last N]` — /btw side-question Q&A history
- `search <term> [--last N]` — Search across session logs for a term
- `tools [--last N] [--session ID]` — Tool usage summary per session
- `errors [--last N]` — Extract errors and failed tool calls
- `conversation [session-id] [--last N]` — Full user/assistant exchanges

## Options

All subcommands support:
- `--last N` — Limit to last N results (default: 10)
- `--all` — Search all projects, not just current
- `--session ID` — Filter to a specific session (partial match)
