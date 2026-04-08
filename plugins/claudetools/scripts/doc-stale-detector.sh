#!/bin/bash
# SessionStart hook — detects documentation quality issues at session start
# Outputs systemMessage listing stale, deprecated, and poorly structured docs.
# Checks: staleness (>90d), deprecated status, missing required frontmatter fields.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
NOW_TS=$(date "+%s")
STALE_LIST=""
DEPRECATED_LIST=""
BROKEN_LIST=""

# Cross-platform date-to-epoch
date_to_epoch() {
  date -d "$1" "+%s" 2>/dev/null \
    || date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null \
    || echo 0
}

# Find all .md files in docs/ directories
MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/docs/archive/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -not -name "_template.md" \
  -type f 2>/dev/null || true)

if [ -z "$MD_FILES" ]; then
  hook_log "no docs found"
  exit 0
fi

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue
  rel_path="${md_file#"$PROJECT_ROOT"/}"

  # Read front matter
  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  if [ "$first_line" != "---" ]; then
    BROKEN_LIST="${BROKEN_LIST}${rel_path} (no frontmatter), "
    continue
  fi

  fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)

  # Check status: deprecated
  status=$(echo "$fm" | { grep '^status:' || true; } | head -1 | sed 's/^status:[[:space:]]*//')
  if [ "$status" = "deprecated" ]; then
    DEPRECATED_LIST="${DEPRECATED_LIST}${rel_path}, "
    continue
  fi

  # Check missing required fields
  has_title=$(echo "$fm" | grep -c '^title:' || true)
  has_desc=$(echo "$fm" | grep -c '^description:' || true)
  if [ "$has_title" -eq 0 ] || [ "$has_desc" -eq 0 ]; then
    BROKEN_LIST="${BROKEN_LIST}${rel_path} (missing title/description), "
    continue
  fi

  # Check updated: date for staleness
  updated=$(echo "$fm" | { grep '^updated:' || true; } | head -1 | sed 's/^updated:[[:space:]]*//')
  if [[ "$updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    updated_ts=$(date_to_epoch "$updated")
    if [ "$updated_ts" -gt 0 ]; then
      days_old=$(( (NOW_TS - updated_ts) / 86400 ))
      if [ "$days_old" -gt 90 ]; then
        STALE_LIST="${STALE_LIST}${rel_path} (${days_old}d), "
      fi
    fi
  fi
done <<< "$MD_FILES"

# Build message
MSG=""
if [ -n "$BROKEN_LIST" ]; then
  BROKEN_LIST="${BROKEN_LIST%, }"
  MSG="Docs missing frontmatter: ${BROKEN_LIST}"
fi
if [ -n "$STALE_LIST" ]; then
  STALE_LIST="${STALE_LIST%, }"
  [ -n "$MSG" ] && MSG="${MSG}. "
  MSG="${MSG}Stale docs (>90d): ${STALE_LIST}"
fi
if [ -n "$DEPRECATED_LIST" ]; then
  DEPRECATED_LIST="${DEPRECATED_LIST%, }"
  [ -n "$MSG" ] && MSG="${MSG}. "
  MSG="${MSG}Deprecated docs: ${DEPRECATED_LIST}"
fi

if [ -n "$MSG" ]; then
  hook_log "found doc issues: $MSG"
  echo "[docs] $MSG. Run /docs-manager audit to fix."
fi

exit 0
