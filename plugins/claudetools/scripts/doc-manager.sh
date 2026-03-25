#!/bin/bash
# PostToolUse hook for Edit|Write — enforces documentation standards
# Validates kebab-case naming, YAML front matter, required fields, and freshness
# for .md files in docs/ directories. Auto-updates the `updated:` date on edit.
# Exit 0 = pass, Exit 1 = violation

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/thresholds.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

HOOK_DECISION="allow"
HOOK_REASON=""

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Skip if no file path
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only process files in docs/ directories
case "$FILE_PATH" in
  */docs/*.md) ;;
  */docs.md) exit 0 ;;
  *) exit 0 ;;
esac

hook_log "processing doc file: $FILE_PATH"

# Skip if file doesn't exist (might have been deleted)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
ISSUES=""

# Check 1: Filename is kebab-case (lowercase alphanumeric with hyphens, .md extension)
if [[ ! "$BASENAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
  ISSUES="${ISSUES}Filename '${BASENAME}' is not kebab-case (must be lowercase, hyphen-separated, e.g. my-doc.md)\n"
fi

# Check 2: File has YAML front matter (starts with ---)
FIRST_LINE=$(head -n 1 "$FILE_PATH" 2>/dev/null || true)
if [ "$FIRST_LINE" != "---" ]; then
  ISSUES="${ISSUES}Missing YAML front matter (file must start with ---)\n"
  # Can't check fields without front matter
  if [ -n "$ISSUES" ]; then
    echo "DOC STANDARDS VIOLATION in $FILE_PATH:" >&2
    echo -e "$ISSUES" >&2
    echo "Fix these issues before continuing." >&2
    HOOK_DECISION="warn"
    HOOK_REASON="doc standards violation: $BASENAME"
    record_hook_outcome "doc-manager" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
    exit 1
  fi
fi

# Extract front matter (between first and second ---)
FRONT_MATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$FILE_PATH" 2>/dev/null || true)

# Check 3: Required fields exist
HAS_TITLE=$(echo "$FRONT_MATTER" | grep -c '^title:' || true)
HAS_DESC=$(echo "$FRONT_MATTER" | grep -c '^description:' || true)
HAS_UPDATED=$(echo "$FRONT_MATTER" | grep -c '^updated:' || true)

if [ "$HAS_TITLE" -eq 0 ]; then
  ISSUES="${ISSUES}Missing required field: title\n"
fi
if [ "$HAS_DESC" -eq 0 ]; then
  ISSUES="${ISSUES}Missing required field: description\n"
fi
if [ "$HAS_UPDATED" -eq 0 ]; then
  ISSUES="${ISSUES}Missing required field: updated\n"
fi

# Check 4: Title is not generic
if [ "$HAS_TITLE" -gt 0 ]; then
  TITLE=$(echo "$FRONT_MATTER" | grep '^title:' | head -1 | sed 's/^title:[[:space:]]*//')
  case "$TITLE" in
    Untitled|Document|TODO|Draft|"")
      ISSUES="${ISSUES}Generic title '${TITLE}' — use a descriptive title\n"
      ;;
  esac
fi

# Check 5: updated: date is not older than 90 days
if [ "$HAS_UPDATED" -gt 0 ]; then
  UPDATED_DATE=$(echo "$FRONT_MATTER" | grep '^updated:' | head -1 | sed 's/^updated:[[:space:]]*//')
  if [[ "$UPDATED_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    # Calculate days since updated (macOS date)
    UPDATED_TS=$(date -j -f "%Y-%m-%d" "$UPDATED_DATE" "+%s" 2>/dev/null || date -d "$UPDATED_DATE" "+%s" 2>/dev/null || echo 0)
    NOW_TS=$(date "+%s")
    if [ "$UPDATED_TS" -gt 0 ]; then
      DAYS_OLD=$(( (NOW_TS - UPDATED_TS) / 86400 ))
      if [ "$DAYS_OLD" -gt 90 ]; then
        ISSUES="${ISSUES}Document is stale: updated ${DAYS_OLD} days ago (${UPDATED_DATE})\n"
      fi
    fi
  fi
fi

# Auto-update the updated: field to today's date
TODAY=$(date "+%Y-%m-%d")
if [ "$HAS_UPDATED" -gt 0 ]; then
  sed -i.bak "s/^updated:.*$/updated: ${TODAY}/" "$FILE_PATH" && rm -f "${FILE_PATH}.bak"
  hook_log "auto-updated 'updated:' field to $TODAY"
fi

# Report violations
if [ -n "$ISSUES" ]; then
  echo "DOC STANDARDS VIOLATION in $FILE_PATH:" >&2
  echo -e "$ISSUES" >&2
  echo "Fix these issues before continuing." >&2
  HOOK_DECISION="warn"
  HOOK_REASON="doc standards violation: $BASENAME"
  record_hook_outcome "doc-manager" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 1
fi

hook_log "doc validation passed: $BASENAME"
record_hook_outcome "doc-manager" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
