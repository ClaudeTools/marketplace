---
title: "Architecture"
description: "How claudetools is structured — the dispatcher pattern, event-to-script mapping, gate scripts, and data directory layout."
---
How claudetools is structured and how its components connect.

## Directory Layout

```
plugin/
  hooks.json              # Maps Claude Code events to shell scripts
  scripts/
    pre-bash-gate.sh      # Dispatcher: PreToolUse:Bash
    pre-edit-gate.sh      # Dispatcher: PreToolUse:Edit|Write
    post-bash-gate.sh     # Dispatcher: PostToolUse:Bash
    post-agent-gate.sh    # Dispatcher: PostToolUse:Agent
    session-stop-gate.sh  # Dispatcher: Stop
    task-completion-gate.sh
    session-end-dispatcher.sh
    session-stop-dispatcher.sh
    validators/           # Modular check functions (one per concern)
    lib/                  # Shared libraries sourced by scripts
  agents/                 # Agent definition files (.md)
  skills/                 # Skill definitions (SKILL.md + scripts/)
  codebase-pilot/         # Symbol index and query CLI
  agent-mesh/             # Multi-agent coordination CLI
  mcp-servers/            # MCP server implementations
```

## Event-to-Script Mapping

`hooks.json` wires Claude Code lifecycle events to dispatcher scripts:

| Event | Script |
|-------|--------|
| `PreToolUse:Bash` | `pre-bash-gate.sh` |
| `PreToolUse:Edit\|Write` | `pre-edit-gate.sh` |
| `PostToolUse:Bash` | `post-bash-gate.sh` |
| `PostToolUse:Agent` | `post-agent-gate.sh` |
| `Stop` | `session-stop-gate.sh` |
| `TeammateIdle` | `session-stop-dispatcher.sh` |

## Dispatcher Pattern

Each gate script is a dispatcher — it orchestrates a set of validators for a specific event type. The pattern is consistent:

1. **Parse input once** — `source lib/hook-input.sh && hook_init` reads stdin, sets `INPUT`, `FILE_PATH`, `MODEL_FAMILY`, and other globals
2. **Source validators** — each validator is a shell function sourced from `validators/`
3. **Run validators in order** — stop on first block (exit code 2) or continue accumulating warnings (exit code 1)
4. **Emit result** — blocks emit JSON to stdout; warnings emit `{"systemMessage": "..."}` to stdout; allows exit 0 silently

```bash
# pre-edit-gate.sh structure (simplified)
source "$SCRIPT_DIR/lib/hook-input.sh" && hook_init
source "$SCRIPT_DIR/validators/blind-edit.sh"
source "$SCRIPT_DIR/validators/task-scope.sh"
# ... more validators
run_pretool_validator "blind-edit" check_blind_edit
run_pretool_validator "task-scope" check_task_scope
```

## Validator Pattern

Each validator in `validators/` is a self-contained shell module:

- Declares a single check function (e.g. `check_blind_edit`)
- Returns exit code `0` (allow), `1` (warn), or `2` (block)
- Writes human-readable output to stdout on non-zero exit
- Reads from globals set by `hook_init`: `INPUT`, `FILE_PATH`, `FILE_EXT`, `MODEL_FAMILY`
- Uses `hook_get_content` for lazy extraction of file content (cached after first call)
- Uses `hook_get_field` for arbitrary jq field extraction

## Skill Loading

Skills are directories under `plugin/skills/`. Each skill contains a `SKILL.md` file with YAML frontmatter:

```yaml
---
name: exploring-codebase
description: Brief description shown in skill picker
argument-hint: [query or file path]
allowed-tools: Read, Bash, Grep, Glob
metadata:
  author: Owen Innes
  version: 2.0.0
  category: navigation
  tags: [explore, find, trace, navigate]
---
```

The `allowed-tools` field restricts which Claude Code tools the skill can use. Skills are invoked with `/skill-name` in the chat interface.

## Agent Definitions

Agents live in `plugin/agents/*.md`. Each file has YAML frontmatter:

```yaml
---
name: architect
description: Invoke description shown in agent picker
model: opus
color: green
tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch
---
```

The `tools` field is the complete tool allowlist for that agent. Read-only agents omit `Edit`, `Write`, `Bash`, `Agent`, and `TeamCreate`.

## MCP Task-System Server

The `mcp-servers/task-system/` server exposes task management as MCP tools (`task_create`, `task_update`, `task_query`, `task_decompose`, `task_progress`). Tasks persist in a JSON store and are accessible to all agents and skills within a session.

## Telemetry Flow

1. Hook scripts call `emit_event` from `lib/telemetry.sh`
2. Events append as JSONL to `logs/events.jsonl`
3. At session end, `session-end-dispatcher.sh` calls `telemetry-sync.sh`
4. `telemetry-sync.sh` batches events and POSTs to `https://telemetry.claudetools.com/v1/events`
5. The local file is truncated on successful upload; rotated at 10 MB

---

## Related

- [Core Concepts](/getting-started/core-concepts/) — high-level introduction to hooks, validators, skills, and agents
- [Extending claudetools](extending.md) — add custom validators, skills, and agents
- [Advanced: Validators](validators.md) — complete validator reference with exit codes
