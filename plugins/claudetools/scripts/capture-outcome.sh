#!/usr/bin/env bash
# capture-outcome.sh — PostToolUse hook: record tool outcome to metrics.db
# Batches inserts to reduce SQLite lock contention. Flushes every 10 outcomes or 30s.
# Must be fast (<10ms). Telemetry never blocks.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/portable-lock.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/thresholds.sh"
source "$(dirname "$0")/lib/worktree.sh"

# sqlite3 required — skip silently if missing
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

# Read hook input from stdin
INPUT=$(cat)

# Extract fields
tool_name=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Must have tool_name at minimum
if [ -z "$tool_name" ]; then
  exit 0
fi

# Ensure DB exists (no-op after first call)
ensure_metrics_db || exit 0

# --- Batch insert: append to spool file, flush when threshold reached ---
SPOOL_DIR=$(session_tmp_path "outcome-spool")
mkdir -p "$SPOOL_DIR" 2>/dev/null || true
SPOOL_FILE="$SPOOL_DIR/pending.sql"
LOCK_FILE="$SPOOL_DIR/flush.lock"

# Append this outcome to the spool (tab-separated for safety)
printf "INSERT INTO tool_outcomes (session_id, tool_name, success, file_path, timestamp) VALUES ('%s', '%s', 1, '%s', datetime('now'));\n" \
  "${session_id//\'/\'\'}" "${tool_name//\'/\'\'}" "${file_path//\'/\'\'}" >> "$SPOOL_FILE" 2>/dev/null || true

# Count pending outcomes
PENDING=$(wc -l < "$SPOOL_FILE" 2>/dev/null || echo 0)

# Check staleness (flush if spool file is >30s old)
STALE=0
if [ -f "$SPOOL_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$SPOOL_FILE" 2>/dev/null || date +%s) ))
  [ "$FILE_AGE" -ge 30 ] && STALE=1
fi

# Flush if 10+ pending or stale
if [ "$PENDING" -ge 10 ] || [ "$STALE" -eq 1 ]; then
  # Non-blocking flush with lock to prevent concurrent flushes (run in background)
  {
    portable_trylock "$LOCK_FILE" || exit 0
    if [ -f "$SPOOL_FILE" ] && [ -s "$SPOOL_FILE" ]; then
      # Wrap in transaction for atomicity
      {
        echo "BEGIN TRANSACTION;"
        cat "$SPOOL_FILE"
        echo "COMMIT;"
      } | sqlite3 "$METRICS_DB" 2>/dev/null || true
      : > "$SPOOL_FILE"  # Truncate after successful flush
    fi
    portable_unlock "$LOCK_FILE"
  } &
fi

exit 0
