#!/usr/bin/env bash
# config-audit-trail.sh — ConfigChange hook: log configuration changes for audit
# Appends JSON lines to logs/config-changes.jsonl. Must be fast.
# Audit logging never blocks — always exits 0.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract fields
source_name=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null) || true
file_path=$(echo "$INPUT" | jq -r '.file_path // "unknown"' 2>/dev/null) || true

# Resolve logs directory relative to plugin root
LOGS_DIR="$(cd "$(dirname "$0")/.." && pwd)/logs"
mkdir -p "$LOGS_DIR"

AUDIT_LOG="$LOGS_DIR/config-changes.jsonl"

# Build timestamp
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append audit entry as JSON line (use jq for safe construction)
# flock to prevent interleaved writes from concurrent sessions
(
  flock -w 1 200 || true
  jq -n --arg ts "$ts" --arg src "$source_name" --arg f "$file_path" \
    '{timestamp: $ts, source: $src, file: $f}' >> "$AUDIT_LOG"
) 200>"${AUDIT_LOG}.lock"

hook_log "config change recorded source=${source_name} file=${file_path}"

# Audit logging should never block
exit 0
