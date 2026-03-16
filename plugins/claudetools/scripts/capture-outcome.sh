#!/usr/bin/env bash
# capture-outcome.sh — PostToolUse hook: record tool outcome to metrics.db
# Must be fast (<10ms). Telemetry never blocks.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"

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

# Insert outcome — parameterised query, no SQL injection risk
sqlite3 "$METRICS_DB" \
  "INSERT INTO tool_outcomes (session_id, tool_name, success, file_path, timestamp) VALUES (?1, ?2, 1, ?3, datetime('now'));" \
  "$session_id" "$tool_name" "$file_path" \
  2>/dev/null || true

exit 0
