#!/bin/bash
# SessionStart hook — detects stale and deprecated documentation
# Outputs JSON systemMessage listing docs older than 90 days or marked deprecated.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
NOW_TS=$(date "+%s")
STALE_LIST=""
DEPRECATED_LIST=""

# Find all .md files in docs/ directories
MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -type f 2>/dev/null || true)

if [ -z "$MD_FILES" ]; then
  hook_log "no docs found"
  exit 0
fi

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue
  fname=$(basename "$md_file")

  # Read front matter
  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  [ "$first_line" != "---" ] && continue

  fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)

  # Check status: deprecated
  status=$(echo "$fm" | { grep '^status:' || true; } | head -1 | sed 's/^status:[[:space:]]*//')
  if [ "$status" = "deprecated" ]; then
    DEPRECATED_LIST="${DEPRECATED_LIST}${fname} (deprecated), "
    continue
  fi

  # Check updated: date
  updated=$(echo "$fm" | { grep '^updated:' || true; } | head -1 | sed 's/^updated:[[:space:]]*//')
  if [[ "$updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    updated_ts=$(date -j -f "%Y-%m-%d" "$updated" "+%s" 2>/dev/null || date -d "$updated" "+%s" 2>/dev/null || echo 0)
    if [ "$updated_ts" -gt 0 ]; then
      days_old=$(( (NOW_TS - updated_ts) / 86400 ))
      if [ "$days_old" -gt 90 ]; then
        STALE_LIST="${STALE_LIST}${fname} (${days_old} days), "
      fi
    fi
  fi
done <<< "$MD_FILES"

# Build message
MSG=""
if [ -n "$STALE_LIST" ]; then
  STALE_LIST="${STALE_LIST%, }"
  MSG="Stale docs: ${STALE_LIST}"
fi
if [ -n "$DEPRECATED_LIST" ]; then
  DEPRECATED_LIST="${DEPRECATED_LIST%, }"
  [ -n "$MSG" ] && MSG="${MSG}. "
  MSG="${MSG}Deprecated docs: ${DEPRECATED_LIST}"
fi

if [ -n "$MSG" ]; then
  hook_log "found stale/deprecated docs: $MSG"
  echo "{\"systemMessage\": \"${MSG}\"}"
fi

exit 0
