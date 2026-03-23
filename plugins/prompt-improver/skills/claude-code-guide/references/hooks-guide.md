# Hooks Guide

How to build Claude Code hooks — from hooks.json configuration to validator patterns.

## Table of Contents

- [Overview](#overview)
- [hooks.json configuration](#hooksjson-configuration)
- [Hook event types](#hook-event-types)
- [Hook script interface](#hook-script-interface)
- [The dispatcher pattern](#the-dispatcher-pattern)
- [The validator pattern](#the-validator-pattern)
- [Common hook input fields](#common-hook-input-fields)
- [Shared libraries](#shared-libraries)
- [Real examples](#real-examples)
- [Gotchas](#gotchas)
- [Verification checklist](#verification-checklist)

---

## Overview

Hooks are shell scripts that Claude Code invokes at specific points during a session. They can inspect tool inputs, block dangerous operations, inject context, track telemetry, and enforce workflows.

Hooks are configured in `plugin/hooks/hooks.json` and implemented as shell scripts in `plugin/scripts/`.

The hook system follows a pipeline model: Claude Code sends JSON on stdin, the hook processes it, and communicates its decision via exit code and stdout/stderr.

---

## hooks.json configuration

The configuration file maps hook events to scripts:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-bash-gate.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-edit-gate.sh"
          }
        ]
      }
    ]
  }
}
```

### Entry fields

| Field | Required | Description |
|---|---|---|
| `matcher` | No | Regex pattern matching tool names (PreToolUse/PostToolUse) or notification types (Notification). If omitted, the hook runs for all tools/events. |
| `hooks[].type` | Yes | Always `"command"` for shell hooks. |
| `hooks[].command` | Yes | Path to the script. Use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths. |
| `hooks[].timeout` | No | Timeout in seconds. The hook is killed if it exceeds this. Set explicit timeouts for I/O-heavy hooks. |
| `hooks[].async` | No | If `true`, the hook runs in the background. Cannot block or warn — use for telemetry and indexing only. |

### Matcher patterns

The `matcher` field is a regex, not a simple string:

- `"Bash"` — matches the Bash tool only
- `"Read|Edit|Write"` — matches any of Read, Edit, or Write
- `"Edit|Write"` — matches Edit or Write
- `"permission_prompt|idle_prompt"` — matches notification types (for Notification hooks)
- Absent matcher — matches everything for that event type

Multiple entries under the same event type are evaluated in order. Each entry that matches runs its hooks.

---

## Hook event types

Claude Code supports these hook events. The hooks.json in this plugin uses most of them:

### Tool lifecycle events

| Event | When it fires | Typical use |
|---|---|---|
| `PreToolUse` | Before a tool executes | Block dangerous commands, enforce read-before-edit, require active tasks |
| `PostToolUse` | After a tool succeeds | Track file reads/edits, validate content, trigger reindexing |
| `PostToolUseFailure` | After a tool fails | Detect failure patterns, log errors for analysis |

### Session lifecycle events

| Event | When it fires | Typical use |
|---|---|---|
| `SessionStart` | When a new session begins | Build codebase index, inject session context, check stale docs |
| `SessionEnd` | When the session closes | Cleanup temp files, finalize metrics, persist session state |
| `SubagentStart` | When a subagent is spawned | Index codebase for subagent context |
| `SubagentStop` | When a subagent completes | Verify subagent output quality. Input JSON includes the subagent's final output and metadata. Hook can inspect quality, flag issues, or log results. See `verify-subagent-independently.sh` for a real implementation. |

### Turn lifecycle events

| Event | When it fires | Typical use |
|---|---|---|
| `Stop` | When the agent finishes a turn (would stop responding) | Quality gates, memory extraction, learning from session |
| `UserPromptSubmit` | When the user submits a prompt | Inject per-prompt context, augment with memory |

### Task and team events

| Event | When it fires | Typical use |
|---|---|---|
| `TaskCompleted` | When a task is marked complete | Validate task quality |
| `TeammateIdle` | When a teammate agent becomes idle | Enforce task quality, prompt git commits |

### System events

| Event | When it fires | Typical use |
|---|---|---|
| `Notification` | When Claude Code sends a notification | Desktop alerts for permission prompts, idle prompts |
| `ConfigChange` | When configuration changes | Audit trail for config modifications |
| `InstructionsLoaded` | When CLAUDE.md/instructions are loaded | Inject dynamic rules based on project context |
| `PermissionRequest` | When Claude requests permission for a tool | Auto-approve safe operations |
| `PreCompact` | Before context compaction | Archive important context before it is lost |
| `PostCompact` | After context compaction | Restore critical context after compaction |
| `WorktreeCreate` | When a new worktree is created | Index codebase in the new worktree |

---

## Hook script interface

### Input (stdin)

Claude Code sends a JSON object on stdin. The structure varies by event type, but common fields include:

```json
{
  "session_id": "abc123",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "old_string": "...",
    "new_string": "..."
  },
  "cwd": "/home/user/project"
}
```

For PostToolUse, the JSON also includes `tool_response` with the tool's output.

### Output (stdout/stderr)

Output format depends on the hook event type:

**PreToolUse — block via JSON stdout:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "block",
    "permissionDecisionReason": "Editing file without reading it first."
  }
}
```

**PreToolUse — warn via systemMessage:**
```json
{
  "systemMessage": "Consider reading the file before editing it."
}
```

**Stop — findings on stderr, exit code is the signal:**
```bash
echo "Incomplete task: tests not run" >&2
exit 1   # warn
```

### Exit codes

Exit code semantics differ between hook event types:

**PreToolUse hooks — always exit 0:**

PreToolUse hooks communicate decisions via JSON on stdout, not exit codes. The script itself always exits 0.

| Decision | JSON output | Exit code |
|---|---|---|
| Allow | (none needed) | 0 |
| Warn | `{"systemMessage": "..."}` | 0 |
| Block | `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "block", ...}}` | 0 |

**Stop hooks — exit code IS the signal:**

| Exit code | Behavior |
|---|---|
| 0 | Allow the agent to stop |
| 1 | Warn — stderr shown to agent, agent continues |
| 2 | Block — agent must address findings before stopping |

**Validator return codes (internal convention):**

Validator functions sourced by dispatchers return 0/1/2 internally. The dispatcher translates these into the appropriate output format:
- Return 0 → allow, continue to next validator
- Return 1 → emit warning (systemMessage JSON for PreToolUse, stderr for Stop)
- Return 2 → block (block JSON for PreToolUse, exit 2 for Stop)

Do not confuse validator return codes with hook exit codes. The dispatcher always exits 0 for PreToolUse regardless of which validator return code triggered.

---

## The dispatcher pattern

Complex hook logic is organized using a dispatcher that sources validators and runs them in sequence. This is the primary pattern in this plugin.

The dispatcher handles three concerns:
1. Parse input once (via `hook_init`)
2. Source validator functions
3. Run validators in order, stopping on first block

### Structure of a dispatcher

From `plugin/scripts/pre-edit-gate.sh`:

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/blind-edit.sh"
source "$SCRIPT_DIR/validators/active-task.sh"
source "$SCRIPT_DIR/validators/task-scope.sh"

# Phase 3: Run validators in order — stop on first block
run_pretool_validator "blind-edit-guard"    validate_blind_edit
run_pretool_validator "require-active-task" validate_active_task
run_pretool_validator "enforce-task-scope"  validate_task_scope

exit 0
```

The `run_pretool_validator` function:
- Calls the validator function
- If it returns exit 2: emits block JSON, records the outcome, and exits immediately
- If it returns exit 1 with output: emits a systemMessage warning
- If it returns exit 0: records allow and continues to the next validator

### Dispatcher variants

**PreToolUse dispatchers** (pre-edit-gate.sh, pre-bash-gate.sh): Stop on first block. Safety-critical — if any validator blocks, no further validators run.

**Stop dispatchers** (session-stop-dispatcher.sh): Aggregate all findings. Run all validators, collect findings on stderr, exit with the maximum exit code. This lets the agent see all issues at once.

---

## The validator pattern

Validators are single-purpose functions sourced by dispatchers. Each validator checks one condition and returns an exit code.

### Structure of a validator

From `plugin/scripts/validators/blind-edit.sh` (simplified):

```bash
# Sourced by dispatcher after hook_init(). Uses globals: INPUT, FILE_PATH, FILE_EXT
# Returns: 0 = allow, 1 = warn, 2 = block

validate_blind_edit() {
  [ -z "$FILE_PATH" ] && return 0          # No file path — skip
  [ ! -f "$FILE_PATH" ] && return 0        # New file — skip
  case "$FILE_EXT" in md|json|yaml) return 0 ;; esac  # Non-code — skip

  source "$(dirname "${BASH_SOURCE[0]}")/../lib/worktree.sh"
  local READS_FILE="/tmp/codebase-pilot-reads-$(get_session_id "$INPUT").jsonl"
  [ ! -f "$READS_FILE" ] && return 0
  grep -qF "\"$FILE_PATH\"" "$READS_FILE" 2>/dev/null && return 0

  echo "Editing '$(basename "$FILE_PATH")' without reading it first." >&2
  return 1
}
```

### Validator design rules

1. **Single responsibility.** Each validator checks exactly one condition.
2. **Use globals from hook_init.** Access `$INPUT`, `$FILE_PATH`, `$FILE_EXT`, `$MODEL_FAMILY` — do not re-parse stdin.
3. **Return early for exempt cases.** Use `return 0` liberally for cases that do not apply.
4. **Output goes to stderr for warnings.** The dispatcher reads stderr and wraps it in JSON.
5. **Guard external calls.** Use `2>/dev/null` and `|| true` on optional operations.
6. **No side effects on allow.** A validator that returns 0 should not produce output or modify state.

---

## Common hook input fields

Fields available in the JSON input (accessed via `hook_get_field`):

| Field | Description | Available in |
|---|---|---|
| `.session_id` | Unique session identifier | All events |
| `.hook_event_name` | The event name (e.g., "PreToolUse") | All events |
| `.tool_name` | Name of the tool being used | PreToolUse, PostToolUse |
| `.tool_input` | Tool's input parameters | PreToolUse, PostToolUse |
| `.tool_input.file_path` | File being read/edited | Read, Edit, Write |
| `.tool_input.command` | Bash command being run | Bash |
| `.tool_input.new_string` | Content being written (Edit) | Edit |
| `.tool_input.content` | Content being written (Write) | Write |
| `.tool_response` | Tool's output/result | PostToolUse |
| `.cwd` | Current working directory | Most events |

Access fields using `hook_get_field '.tool_name'` or the raw `$INPUT` variable with jq.

---

## Shared libraries

Hook scripts share common functionality through libraries in `plugin/scripts/lib/`:

### hook-input.sh

The core library. Provides `hook_init` (reads stdin, sources deps, sets globals), `hook_get_content` (lazy extraction of written content), and `hook_get_field` (arbitrary jq field extraction).

Always source and call `hook_init` before anything else:

```bash
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init
```

### worktree.sh

Worktree-aware path resolution. Provides `get_repo_root` (main repo root even from worktrees), `get_worktree_root` (current worktree root), `is_worktree` (check if in a worktree), `get_session_id` (session ID with fallback chain), and `session_tmp_path` (session-scoped temp files).

```bash
source "$SCRIPT_DIR/lib/worktree.sh"
local root
root=$(get_repo_root)
local sid
sid=$(get_session_id "$INPUT")
```

### Other libraries

- `hook-log.sh` — Logging with hook name context
- `ensure-db.sh` — SQLite metrics database initialization
- `adaptive-weights.sh` — Adaptive threshold management
- `telemetry.sh` — Structured telemetry event emission

---

## Real examples

| Hook | Event | What it does |
|---|---|---|
| `pre-bash-gate.sh` | PreToolUse:Bash | Dispatches dangerous-bash, ai-safety, and unasked-restructure validators |
| `pre-edit-gate.sh` | PreToolUse:Edit\|Write | Dispatches blind-edit, active-task, task-scope, research-backing, bulk-edit validators |
| `track-file-reads.sh` | PostToolUse:Read | Records reads to session-scoped JSONL; powers the blind-edit validator |
| `session-stop-dispatcher.sh` | Stop | Runs task-quality and stop-gate; blocks stopping with incomplete work |
| `session-index.sh` | SessionStart | Builds/updates codebase navigation index (30s timeout) |
| `memory-index.sh` | PostToolUse:Edit\|Write | Async — updates memory index in background, cannot block |

---

## Gotchas

1. **Stop fires on every turn end, not session close.** The `Stop` event fires whenever the agent would stop responding within a turn. For cleanup that should happen once when the session truly ends, use `SessionEnd`. See the SKILL.md universal principles section.

2. **PPID is not session ID.** `$PPID` changes depending on invocation context. Always use `get_session_id` from `lib/worktree.sh`, which reads `.session_id` from hook input JSON first and falls back through `$SESSION_ID` env var, then `$PPID`.

3. **Consume stdin before everything.** `hook_init` reads stdin into the `$INPUT` variable. If any sourced library or command reads stdin first, the hook data is gone. Place `source lib/hook-input.sh && hook_init` at the very top, before other sources.

4. **PreToolUse always exits 0.** Block/allow decisions are in JSON stdout, not the exit code. This is different from Stop hooks where the exit code IS the signal.

5. **Async hooks cannot block.** Hooks with `"async": true` run in the background. They cannot block tool use, emit warnings, or inject systemMessages. Use only for telemetry, indexing, and logging.

6. **Matcher is a regex.** `"matcher": "Read"` matches the Read tool. `"matcher": "Read|Edit"` matches either. An absent matcher matches all tools for that event.

7. **Timeout kills the hook.** If a hook exceeds its timeout, Claude Code kills it. Set realistic timeouts. For hooks that do network calls or heavy I/O, use the `async` flag.

8. **Multiple hooks per event run in sequence.** If two hook entries match the same event+tool, both run. Within a single entry, multiple hooks also run in sequence. Order matters for PreToolUse — first block wins.

9. **Guard external tool calls.** Not every environment has `jq`, `sqlite3`, or other tools. Use `command -v tool &>/dev/null || { exit 0; }` to fail gracefully.

10. **Worktree paths.** In worktrees, `$(pwd)` returns the worktree path, not the main repo root. Use `get_repo_root` from `lib/worktree.sh`. See `references/skills-guide.md` for the worktree library details.

---

## Verification checklist

Before considering a hook complete:

- [ ] Script starts with `set -euo pipefail`
- [ ] `hook_init` is called before any other operation (stdin consumed first)
- [ ] Exit codes follow the correct convention for the hook type
- [ ] External tool calls are guarded with `command -v` or `2>/dev/null || true`
- [ ] Session identity uses `get_session_id`, not `$PPID` directly
- [ ] Paths use `get_repo_root` or `$SCRIPT_DIR`, not `$(pwd)`
- [ ] Timeout is set in hooks.json for hooks doing I/O
- [ ] Async flag is set for non-blocking background work
- [ ] Matcher regex is correct (test with sample tool names)
- [ ] Hook is registered in `plugin/hooks/hooks.json`
- [ ] BATS tests exist in `tests/bats/hooks/`
- [ ] Script syntax passes: `bash -n script.sh`
- [ ] Synchronous hooks complete in under 100ms

See `references/skills-guide.md` if the hook supports a skill. See `references/agents-guide.md` if the hook involves subagent lifecycle events.
