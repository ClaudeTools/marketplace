---
title: "Configuration"
description: "Environment variables and adaptive threshold tuning — quiet mode, data directory paths, and per-project threshold overrides."
---
Environment variables and threshold tuning for claudetools.

## Environment Variables

### `CLAUDE_HOOKS_QUIET`

Set to `1` to skip non-safety hooks. Safety-critical hooks (`pre-bash-gate`) always run regardless of this setting. All other hooks exit early when quiet mode is active.

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

Useful during high-throughput sessions where hook latency is noticeable.

### `CLAUDE_PLUGIN_ROOT`

Path to the installed plugin directory. Set automatically by the Claude Code plugin system when the plugin is loaded. Scripts use this to locate sibling files (validators, lib, codebase-pilot).

```bash
# Typically set to something like:
CLAUDE_PLUGIN_ROOT=/home/user/.claude/plugins/cache/claudetools/3.x.x
```

When `CLAUDE_PLUGIN_ROOT` points to a versioned cache path (matching `*/plugins/cache/*/X.Y.Z`), the data directory (`metrics.db`, telemetry logs) is placed one level above the version directory so it survives plugin upgrades.

## Adaptive Thresholds

Thresholds that control hook sensitivity are defined in `plugin/scripts/lib/adaptive-weights.sh` via the `get_threshold` function. All values are hardcoded constants — DB-based adaptive tuning was removed (see commit 701b12f).

| Threshold | Default | Used by |
|-----------|---------|---------|
| `edit_frequency_limit` | 3 | edit-frequency-guard |
| `failure_loop_limit` | 3 | deploy-loop-detector |
| `diverse_failure_total_warn` | 5 | failure-pattern-detector |
| `churn_warning` | 2.0 | inject-session-context |
| `failure_warning` | 10 | inject-session-context |
| `uncommitted_file_limit` | 5 | enforce-git-commits |
| `large_change_threshold` | 15 | session-stop-gate |
| `ai_audit_diff_threshold` | 30 | session-stop-gate |
| `ts_any_limit` | 3 | task-quality |
| `ts_as_any_limit` | 2 | task-quality |
| `ts_ignore_limit` | 1 | task-quality |
| `stub_sensitivity` | 1.0 | stubs validator |
| `memory_confidence_inject` | 0.7 | inject-session-context |
| `memory_decay_rate` | 0.95 | memory-consolidate |
| `memory_decay_window_days` | 30 | memory-consolidate |
| `memory_prune_threshold` | 0.1 | memory-consolidate |
| `memory_retrieval_limit` | 3 | active-memory |
| `read_warn_lines` | 2000 | enforce-read-efficiency |
| `read_block_lines` | 10000 | enforce-read-efficiency |
| `outcome_retention_days` | 90 | aggregate-session |

To override a threshold, modify the `case` statement in `adaptive-weights.sh`. Threshold overrides are also seeded into `metrics.db` (table `threshold_overrides`) on first run; direct DB edits also work but are lost on reinstall.

## Memory System

The memory system stores project context in two places:

- **Markdown files** — `~/.claude/projects/<slug>/memory/*.md`, one file per memory entry
- **SQLite index** — `data/metrics.db` (table `memories`), kept in sync with the markdown files

The `memory-consolidate` validator syncs files to the DB, decays confidence of stale entries, and prunes memories below the `memory_prune_threshold`. The FTS5 virtual table (`memories_fts`) enables full-text search at injection time.

Memory injection happens in `inject-session-context.sh` — memories with confidence above `memory_confidence_inject` (default 0.7) are prepended to the session context at session start.
