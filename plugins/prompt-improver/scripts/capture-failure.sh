#!/usr/bin/env bash
# capture-failure.sh — PostToolUseFailure hook: record failure to metrics.db
# Companion to capture-outcome.sh. Ensures failures (success=0) are tracked
# in the same database, making the self-learning pipeline complete.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"

if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

INPUT=$(cat)

tool_name=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

if [ -z "$tool_name" ]; then
  exit 0
fi

ensure_metrics_db || exit 0

# Parameterised query — no SQL injection risk
sqlite3 "$METRICS_DB" \
  "INSERT INTO tool_outcomes (session_id, tool_name, success, file_path, timestamp) VALUES (?1, ?2, 0, ?3, datetime('now'));" \
  "$session_id" "$tool_name" "$file_path" \
  2>/dev/null || true

exit 0
