---
description: List all installed hooks, validators, and their recent performance metrics.
argument-hint: ""
---

# /hook-inventory

List all installed hooks, validators, and their recent performance metrics.

## Examples

| User says | What to do |
|---|---|
| `/hook-inventory` | Show full hook table with 30-day metrics |

## Keywords

hooks, validators, guardrails, what hooks exist, hook inventory, list hooks

## Workflow

1. Parse `plugin/hooks/hooks.json` to extract all hook entries:
   - Event type (PreToolUse, PostToolUse, Stop, SubagentStop, SessionStart, etc.)
   - Matcher pattern (Bash, Read, Edit|Write, Agent, Grep, etc.)
   - Script path (basename only for readability)
   - Timeout value
   - Whether async

2. For each validator script in `plugin/scripts/validators/`:
   - Read the comment header (first 5 lines) to extract what it checks
   - Determine exit code behavior: warn (exit 1) or block (exit 2)

3. Read recent hook outcomes from `plugin/logs/hooks.log` (if it exists):
   - For each hook with 10+ fires in the last 30 days: show total fires, block count, warn count, allow count
   - Highlight any hook with >30% block rate (possible false positive issue)
   - Highlight any hook with 0% block rate over 100+ fires (possible dead hook)

4. Present as a formatted markdown table:

| Event | Matcher | Script | Behavior | 30d Fires | Block% | Warn% |
|---|---|---|---|---|---|---|
| PreToolUse | (global) | enforce-user-stop.sh | block | ... | ... | ... |
| PreToolUse | Bash | pre-bash-gate.sh | dispatches | ... | ... | ... |

5. After the table, list any hooks that could not be parsed or scripts that are referenced but missing.

## Edge cases

- **No hooks.log**: Show the table from hooks.json only; note "No metrics available — hooks.log not found."
- **hooks.json missing**: Tell the user: "hooks.json not found. Hooks may not be installed."
- **Script file missing**: Flag the entry with a `[MISSING]` marker in the Script column.
- **Async hooks**: Mark with `(async)` in the Behavior column — these do not block tool execution.
