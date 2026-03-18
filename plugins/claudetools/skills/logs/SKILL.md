---
name: logs
description: Extract and query Claude Code session logs — /btw side-questions, conversation history, tool usage, errors, and search. Use when the user says logs, btw logs, session logs, show logs, side questions, conversation history, tool usage, error log, search sessions, or any natural language request about session history.
argument-hint: <natural language query> — e.g. "btw all from today", "search memory yesterday", "tools this week"
allowed-tools: Read, Bash, Grep, Glob, Write
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.1.0
  category: meta
  tags: [logs, btw, sessions, search, tools, errors]
---

# Session Logs

Extract and query Claude Code JSONL session logs. Accepts natural language — you interpret the user's intent and build the right command.

## Workflow

### Step 1: Interpret the user's request

Parse `${ARGUMENTS}` as natural language. Map it to a `logs.sh` subcommand + flags:

| User says | Subcommand | Flags |
|-----------|------------|-------|
| "btw", "side questions", "btw history" | `btw` | |
| "btw all from today" | `btw` | `--all --from today` |
| "search X", "find X in logs" | `search X` | |
| "search X from yesterday" | `search X` | `--from yesterday` |
| "tools", "tool usage" | `tools` | |
| "errors", "what failed" | `errors` | |
| "conversation", "show session" | `conversation` | |
| "summary", "overview", (empty) | `summary` | |
| "all from today", "everything today" | `summary` | `--all --from today` |
| "last 5", "last N" | (inferred) | `--last N` |
| "from yesterday", "since Monday" | (inferred) | `--from <value>` |
| "across all projects" | (inferred) | `--all` |

The `--from` flag accepts: `today`, `yesterday`, `N days ago`, `this week`, `YYYY-MM-DD`.

If the intent is ambiguous, default to `summary`.

### Step 2: Run the command

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/logs/scripts/logs.sh <subcommand> <flags>
```

### Step 3: Present results

- **Small output** (< 50 lines): Show the full output, formatted with markdown structure (headers per session, code blocks for content).
- **Large output** (50+ lines): Show a **structured overview** instead:
  - Total count (e.g. "Found 23 /btw conversations from today across 8 sessions")
  - Top 3-5 entries shown in detail
  - Remaining entries summarized (dates, topics, counts)
- **No results**: Tell the user "No session data found for the current project. Claude Code stores session logs in ~/.claude/projects/ — they appear after at least one session."

### Step 4: Offer dump

After presenting results, if any data was found, ask the user:

> "Want me to save the full output to a file?"

If they say yes, re-run the command with `--last 999` (to remove truncation limits) and redirect to `/tmp/claude-logs-<timestamp>.txt`:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/logs/scripts/logs.sh <subcommand> <flags> --last 999 > /tmp/claude-logs-$(date +%Y%m%d-%H%M%S).txt
```
Report the file path back.

## Available subcommands (for reference)

- `summary` — One-line overview per session: date, turns, tools, size, topic
- `btw` — /btw side-question Q&A history
- `search <term>` — Search across session logs for a term
- `tools` — Tool usage summary per session
- `errors` — Extract errors and failed tool calls
- `conversation [session-id]` — Full user/assistant exchanges

## Available flags (for reference)

- `--last N` — Limit to last N results (default: 10)
- `--all` — Search all projects, not just current
- `--session ID` — Filter to a specific session (partial match)
- `--from VALUE` — Filter by date: today, yesterday, "N days ago", "this week", YYYY-MM-DD
