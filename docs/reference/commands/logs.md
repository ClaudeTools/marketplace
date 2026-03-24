---
title: /logs
parent: Slash Commands
grand_parent: Reference
nav_order: 5
---

# /logs

Extract and query Claude Code session logs — `/btw` side-questions, conversation history, tool usage, errors, and search.

## Invocation

```
/logs [subcommand] [args]
```

Default subcommand (no argument): `summary`

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `summary` | Session overview (default) |
| `btw` | Last `/btw` Q&A |
| `search "<term>"` | Search for a term across session logs |
| `tools` | Tool usage per session |
| `errors` | Errors and failures |
| `conversation` | Latest full conversation |

## Flags (all subcommands)

| Flag | Effect |
|------|--------|
| `--last N` | Limit results (btw defaults to 1, others to 10) |
| `--all` | Include all projects |
| `--session ID` | Filter to a specific session |
| `--from VALUE` | Date filter: `today`, `yesterday`, `"N days ago"`, `this week`, `YYYY-MM-DD` |

## Examples

```
/logs
/logs btw
/logs btw --last 5
/logs btw --all --from today
/logs search "webhook"
/logs tools
/logs errors
/logs conversation
/logs summary --from yesterday
```

## Notes

- Logs appear in `~/.claude/projects/` after at least one session.
- Output over 50 lines is summarized with an offer to save the full output to a file.
