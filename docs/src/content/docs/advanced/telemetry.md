---
title: "Telemetry"
description: "What claudetools collects, where events are stored locally, how uploads work, and how to opt out completely."
---
What claudetools collects, where it goes, and how to opt out.

## What Is Collected

Hook scripts emit structured events via `lib/telemetry.sh`. Each event record contains:

| Field | Description |
|-------|-------------|
| `install_id` | Stable anonymous UUID generated on first install, persisted in `data/.install-id` |
| `version` | Plugin version from `.claude-plugin/plugin.json` |
| `os` | OS identifier (`linux`, `darwin`, `windows`) |
| `timestamp` | ISO 8601 UTC timestamp |
| `component` | Hook or gate that emitted the event (e.g. `pre-edit-gate`) |
| `event` | Validator name (e.g. `blind-edit`) |
| `decision` | `allow`, `warn`, or `block` |
| `duration_ms` | Time the validator took to run |

Additional fields are merged from the `extra_json` parameter — typically the reason text on blocks and warns.

No file content, code, user messages, or personally identifiable information is included.

## Local Storage

Events are appended as JSONL to `logs/events.jsonl` inside the plugin data directory. The file is rotated when it exceeds 10 MB (renamed to `events.jsonl.1`). Rotation is serialised with `flock` to prevent concurrent-write corruption.

## Upload

At session end, `session-end-dispatcher.sh` calls `telemetry-sync.sh`, which batches events and POSTs them to:

```
https://telemetry.claudetools.com/v1/events
```

The local file is truncated on a successful upload. On failure, events remain in place and the pending count is logged to `hook-log.sh`.

## Metrics Database Schema

Hook outcomes are also written to `data/metrics.db` (SQLite) for local use by validators and the training framework. Key tables:

| Table | Purpose |
|-------|---------|
| `hook_outcomes` | Per-event decision log (hook, decision, model family, timestamp) |
| `session_metrics` | Aggregated per-session statistics |
| `threshold_overrides` | Current threshold values with min/max bounds |
| `threshold_history` | History of threshold changes with precision/recall at change time |
| `model_profiles` | Per-model-family threshold multipliers |
| `memories` | Active memory entries with FTS5 index |
| `tool_outcomes` | Per-tool-call success/failure log |

The DB is local-only — it is not uploaded.

## Opting Out

Set `CLAUDE_HOOKS_QUIET=1` to suppress non-safety hooks entirely, which also prevents telemetry events from being emitted. To disable only the upload step, remove or rename `scripts/lib/telemetry-sync.sh`.

---

## Related

- [Configuration](configuration.md) — `CLAUDE_HOOKS_QUIET` and other environment settings
- [Reference: /logs command](/reference/commands/logs/) — query locally stored session logs
- [Reference: /session-dashboard command](/reference/commands/session-dashboard/) — local metrics view using the metrics.db data
