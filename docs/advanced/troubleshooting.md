---
title: Troubleshooting
parent: Advanced
nav_order: 7
---

# Troubleshooting

Common issues and how to resolve them.

## Hooks Not Firing

**Symptom:** validators are not running; blocks and warnings do not appear.

1. Confirm the plugin is loaded — run `/claude-code-guide` in the chat. If the skill is unavailable, the plugin is not installed.
2. Check `CLAUDE_HOOKS_QUIET` — if set to `1`, all non-safety hooks are suppressed. Unset it to restore full hook coverage.
3. Check `hooks.json` — the event names must exactly match Claude Code's event identifiers. A typo in `PreToolUse:Edit|Write` will silently drop those events.
4. Check script permissions — gate scripts must be executable: `chmod +x plugin/scripts/*.sh`

## Codebase-Pilot Not Indexing

**Symptom:** `/exploring-codebase` returns no results; `find-symbol` cannot locate known functions.

Run the doctor command:

```bash
node plugin/codebase-pilot/dist/cli.js doctor
```

This checks that the index DB exists, is writable, and contains entries. If it reports a missing index, run:

```bash
node plugin/codebase-pilot/dist/cli.js index
```

A full reindex takes 10–60 seconds depending on project size. If the index exists but symbols are missing, the file may not have been indexed yet — run `index-file <path>` for targeted reindexing.

The `session-index.sh` hook auto-indexes at session start. If it fails silently, check that `node` is in PATH when Claude Code launches.

## Memory Issues

**Symptom:** session context is very large; Claude appears to be injecting stale or irrelevant memories.

- Run `/memory` to inspect what is currently stored
- Lower the `memory_retrieval_limit` threshold (default 3) in `adaptive-weights.sh` to inject fewer memories per session
- Raise `memory_confidence_inject` (default 0.7) to only inject high-confidence memories
- Run `/memory` with the `prune` argument to manually trigger pruning of low-confidence entries
- If the `memories` FTS index is corrupt, delete `data/metrics.db` — it will be recreated from the markdown files on next run

## High Block Rates

**Symptom:** blocks are firing too aggressively; legitimate operations are being rejected.

Use the `/field-review` skill to review recent hook decisions and reclassify false positives. This feeds back into the training framework.

To raise a specific threshold, edit `adaptive-weights.sh`:

```bash
case "$metric_name" in
  edit_frequency_limit) echo "5" ;;  # was 3
  ...
```

The `stub_sensitivity` threshold controls how aggressively the stubs validator fires — lower values are more permissive.

If a specific validator is firing incorrectly on your project type, check if `hook-skip.sh` should be classifying your file extension as a test or config file.

## Performance — Hook Latency

**Symptom:** every tool call takes noticeably longer than expected.

Enable quiet mode for non-interactive work:

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

This skips all hooks except safety-critical ones (`pre-bash-gate` ignores quiet mode).

If quiet mode is not appropriate, profile which validator is slow by adding `time` wrappers around individual `run_pretool_validator` calls in the gate script. Common causes:

- `semantic-agent.sh` — makes a secondary model API call; disable if latency is critical
- `pilot-query.sh` calls — codebase-pilot CLI starts Node.js on each call; warm up the index at session start
- SQLite writes — if `metrics.db` is on a slow filesystem, move the data directory via `CLAUDE_PLUGIN_ROOT`

## Metrics DB Locked

**Symptom:** `database is locked` errors in hook logs.

The DB uses WAL mode and a 5-second busy timeout. Concurrent locks from multiple sessions should self-resolve. If the lock persists:

```bash
sqlite3 data/metrics.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

If the DB is corrupt, delete it — `ensure_metrics_db` recreates it with the full schema on next run. Existing hook outcomes and memories will be lost.

## Publish Token Expired

**Symptom:** CI publish workflow fails with authentication error.

Refresh the token before pushing:

```bash
gh secret set PUBLIC_REPO_TOKEN --repo ClaudeTools/marketplace-dev --body "$(gh auth token)"
```

See the [publish workflow reference](/reference/publish/) for the full publish sequence.
