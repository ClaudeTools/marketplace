---
title: Shared Libraries
parent: Advanced
nav_order: 4
---

# Shared Libraries

Reusable shell modules in `plugin/scripts/lib/`. All are designed to be sourced (`source lib/foo.sh`), not executed directly.

## `adaptive-weights.sh`

Hook thresholds and outcome recording.

**`get_threshold(metric_name)`** — returns the numeric threshold for a named metric. All values are hardcoded constants. Returns `3` for any unknown metric name.

**`record_hook_outcome(hook_name, event_type, decision, tool_name, threshold_name, threshold_used, model_family)`** — writes a row to the `hook_outcomes` table in `metrics.db`. Runs asynchronously in a subshell; no-ops if sqlite3 is unavailable or the DB does not exist.

**`classify_outcome(outcome_id, is_correct)`** — marks a previously recorded outcome as correct or incorrect. Used by the training framework.

## `detect-project.sh`

Universal project type detection.

**`detect_project_type()`** — inspects the working directory and sets `PROJECT_TYPE` to one of: `node`, `python`, `rust`, `go`, `java`, `dotnet`, `ruby`, `swift`, or `general`. Detection is file-based (checks for `package.json`, `Cargo.toml`, `go.mod`, etc.). Safe to call multiple times; result is cached after first call.

## `ensure-db.sh`

SQLite database initialisation.

Sets `METRICS_DB` to the stable data path (one level above versioned installs). **`ensure_metrics_db()`** creates `metrics.db` with the full schema if it does not exist, then runs migrations to add tables that may be missing in older installations. Enables WAL mode and a 5-second busy timeout for concurrent write safety.

Tables created: `tool_outcomes`, `session_metrics`, `threshold_overrides`, `project_memories`, `memory_effectiveness`, `hook_outcomes`, `threshold_history`, `model_profiles`, `memories` (with FTS5 virtual table and sync triggers), and training framework tables (`reference_codebases`, `prompt_chains`, `chain_steps`, `chain_executions`, `step_executions`, `deviations`, `guardrail_gaps`).

## `hook-input.sh`

Input parsing and global setup for all hook scripts.

**`hook_init()`** — reads the full JSON payload from stdin into `INPUT`, extracts common fields (`FILE_PATH`, `FILE_EXT`, `BASENAME`, `MODEL_FAMILY`, `SESSION_ID`), sources `adaptive-weights.sh`, `ensure-db.sh`, and `telemetry.sh`, and installs an EXIT trap that records final hook outcome telemetry.

**`hook_get_content()`** — lazily extracts `new_string` or `content` from `INPUT` (cached after first call). Avoids repeated jq subshells for content-heavy validators.

**`hook_get_field(path)`** — extracts an arbitrary jq path from `INPUT`. Example: `hook_get_field '.tool_input.command'`.

## `hook-skip.sh`

Skip-pattern library for content validation hooks.

Pure case-statement functions with no subshells. Each takes a file path as `$1` and returns `0` (skip) or `1` (do not skip).

| Function | Skips when |
|----------|-----------|
| `is_test_file` | Path matches `*.test.*`, `*.spec.*`, `__tests__`, `__mocks__`, `fixtures`, `*.mock.*`, `*.stories.*` |
| `is_doc_file` | Path matches `*.md`, `*.txt`, `*.rst`, `*.adoc` |
| `is_config_file` | Path matches `*.json`, `*.yaml`, `*.yml`, `*.toml`, `*.lock`, `*.config.*`, `*.rc`, `.env*` |
| `is_binary_file` | Path matches lock files, images, fonts, and other binary assets |

## `pilot-query.sh`

Wrapper library for codebase-pilot CLI queries.

**`pilot_find_symbol(name)`** — runs `codebase-pilot find-symbol` and returns results. Guards against double-sourcing with `_PILOT_QUERY_LOADED`. Auto-detects the plugin root from `CLAUDE_PLUGIN_ROOT` or relative to the library file location.

## `task-history.js`

Node.js module for reading task history from the task-store. Used by validators that need to understand what task is currently active and what work has been completed.

## `task-store.js`

Node.js module for reading and writing the persistent task JSON store. Provides the data layer for the MCP task-system server.

## `telemetry.sh`

Structured local event logging.

**`emit_event(component, event, decision, duration_ms, extra_json)`** — appends a JSONL record to `logs/events.jsonl`. No jq, no subshells, no external dependencies. All state is cached after `_telemetry_ensure_init` is called.

Fields written: `install_id`, `version`, `os`, `timestamp`, `component`, `event`, `decision`, `duration_ms`, plus the `extra_json` fields merged in.

Log rotation occurs at 10 MB — the current file is moved to `events.jsonl.1`. Rotation is wrapped in `flock` to prevent concurrent rotation races.

## `telemetry-sync.sh`

Background batch uploader for `events.jsonl`.

**`telemetry_sync()`** — POSTs events in batches to `https://telemetry.claudetools.com/v1/events`. Called from `session-end-dispatcher.sh`. Truncates the local file on successful upload. Leaves unsynced events in place on failure, logging the pending count.

## `worktree.sh`

Worktree-aware path and session identity utilities.

| Function | Returns |
|----------|---------|
| `get_repo_root()` | Main repository root, even when called from inside a worktree |
| `get_worktree_root()` | Current worktree root, or repo root if not in a worktree |
| `is_worktree()` | `0` if inside a git worktree, `1` otherwise |
| `get_session_id([input])` | Session ID from hook input JSON, `$SESSION_ID`, or `$PPID` in that priority order |
| `session_tmp_path(name)` | `/tmp/claude-{name}-{session_id}` — stable temp path scoped to the session |
