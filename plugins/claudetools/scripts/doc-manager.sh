#!/bin/bash
# PostToolUse hook for Edit|Write — enforces documentation standards
# Validates frontmatter schema on .md files in docs/ directories:
#   Required: title (not generic, not empty), description (10+ chars), updated (ISO, not future, <90d)
#   Recommended: status (valid enum), type (valid enum), author, tags
# Auto-updates the `updated:` date on edit.
# Exit 0 = pass, Exit 1 = violation (warn, does not block)

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

# Only process .md files in docs/ directories
case "$FILE_PATH" in
  */docs/*.md) ;;
  */docs.md) exit 0 ;;
  *) exit 0 ;;
esac

# Skip index.md and templates (generated files)
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  index.md|_template.md) exit 0 ;;
esac

hook_log "processing doc file: $FILE_PATH"

# Skip if file doesn't exist (might have been deleted)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Skip files in archive/
case "$FILE_PATH" in
  */docs/archive/*) exit 0 ;;
esac

# Valid enum values
VALID_STATUSES="draft active review deprecated"
VALID_TYPES="guide reference decision tutorial overview changelog api runbook"

ERRORS=""
WARNINGS=""
SUGGESTIONS=""

# Cross-platform date-to-epoch
date_to_epoch() {
  date -d "$1" "+%s" 2>/dev/null \
    || date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null \
    || echo 0
}

# --- Check 1: Filename is kebab-case ---
if [[ ! "$BASENAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
  WARNINGS="${WARNINGS}  - Filename '${BASENAME}' is not kebab-case (use lowercase-with-hyphens.md)\n"
fi

# --- Check 2: File has YAML front matter ---
FIRST_LINE=$(head -n 1 "$FILE_PATH" 2>/dev/null || true)
if [ "$FIRST_LINE" != "---" ]; then
  ERRORS="${ERRORS}  - Missing YAML front matter (file must start with ---)\n"
  ERRORS="${ERRORS}    Fix: Add to top of file:\n"
  ERRORS="${ERRORS}    ---\n"
  ERRORS="${ERRORS}    title: <descriptive title>\n"
  ERRORS="${ERRORS}    description: <one-line summary>\n"
  ERRORS="${ERRORS}    updated: $(date '+%Y-%m-%d')\n"
  ERRORS="${ERRORS}    status: draft\n"
  ERRORS="${ERRORS}    type: guide\n"
  ERRORS="${ERRORS}    ---\n"
  # Can't check fields without front matter — report and exit
  echo "DOC STANDARDS: $FILE_PATH" >&2
  echo -e "$ERRORS" >&2
  HOOK_DECISION="warn"
  HOOK_REASON="missing frontmatter: $BASENAME"
  record_hook_outcome "doc-manager" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 1
fi

# Extract front matter
FM=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$FILE_PATH" 2>/dev/null || true)

# Helper: get field value
fm_field() {
  echo "$FM" | { grep "^${1}:" || true; } | head -1 | sed "s/^${1}:[[:space:]]*//"
}

# --- Required field: title ---
TITLE=$(fm_field "title")
if [ -z "$TITLE" ]; then
  ERRORS="${ERRORS}  - Missing required field: title\n"
else
  case "$TITLE" in
    Untitled|Document|TODO|Draft|Title|"Document Title"|"New Document"|"")
      WARNINGS="${WARNINGS}  - Generic title '${TITLE}' — use a descriptive title\n"
      ;;
  esac
fi

# --- Required field: description ---
DESC=$(fm_field "description")
if [ -z "$DESC" ]; then
  ERRORS="${ERRORS}  - Missing required field: description\n"
elif [ "${#DESC}" -lt 10 ]; then
  WARNINGS="${WARNINGS}  - Description too short (${#DESC} chars) — aim for a meaningful one-line summary\n"
fi

# --- Required field: updated ---
UPDATED=$(fm_field "updated")
NOW_TS=$(date "+%s")
if [ -z "$UPDATED" ]; then
  WARNINGS="${WARNINGS}  - Missing field: updated — add updated: YYYY-MM-DD\n"
elif [[ "$UPDATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  UPDATED_TS=$(date_to_epoch "$UPDATED")
  if [ "$UPDATED_TS" -gt 0 ]; then
    if [ "$UPDATED_TS" -gt "$NOW_TS" ]; then
      WARNINGS="${WARNINGS}  - Date '${UPDATED}' is in the future\n"
    fi
    DAYS_OLD=$(( (NOW_TS - UPDATED_TS) / 86400 ))
    if [ "$DAYS_OLD" -gt 90 ]; then
      WARNINGS="${WARNINGS}  - Stale: updated ${DAYS_OLD} days ago (${UPDATED})\n"
    fi
  fi
else
  WARNINGS="${WARNINGS}  - Date '${UPDATED}' is not ISO format — use YYYY-MM-DD\n"
fi

# --- Recommended field: status ---
STATUS=$(fm_field "status")
if [ -z "$STATUS" ]; then
  SUGGESTIONS="${SUGGESTIONS}  - Add status: draft|active|review|deprecated\n"
else
  valid=false
  for v in $VALID_STATUSES; do [ "$STATUS" = "$v" ] && valid=true; done
  if [ "$valid" = false ]; then
    WARNINGS="${WARNINGS}  - Invalid status '${STATUS}' — use: ${VALID_STATUSES}\n"
  fi
fi

# --- Recommended field: type ---
TYPE=$(fm_field "type")
if [ -z "$TYPE" ]; then
  SUGGESTIONS="${SUGGESTIONS}  - Add type: guide|reference|decision|tutorial|overview|changelog|api|runbook\n"
else
  valid=false
  for v in $VALID_TYPES; do [ "$TYPE" = "$v" ] && valid=true; done
  if [ "$valid" = false ]; then
    SUGGESTIONS="${SUGGESTIONS}  - Unknown type '${TYPE}' — standard types: ${VALID_TYPES}\n"
  fi
fi

# --- Recommended field: author ---
AUTHOR=$(fm_field "author")
if [ -z "$AUTHOR" ]; then
  SUGGESTIONS="${SUGGESTIONS}  - Add author: <name> for maintenance tracking\n"
fi

# --- Recommended field: tags ---
HAS_TAGS=$(echo "$FM" | grep -c '^tags:' || true)
if [ "$HAS_TAGS" -eq 0 ]; then
  SUGGESTIONS="${SUGGESTIONS}  - Add tags: [keyword1, keyword2] for categorization\n"
fi

# --- Auto-update the updated: field ---
TODAY=$(date "+%Y-%m-%d")
if echo "$FM" | grep -q '^updated:'; then
  sed -i.bak "s/^updated:.*$/updated: ${TODAY}/" "$FILE_PATH" && rm -f "${FILE_PATH}.bak"
  hook_log "auto-updated 'updated:' field to $TODAY"
fi

# --- Report findings ---
HAS_ISSUES=false

if [ -n "$ERRORS" ] || [ -n "$WARNINGS" ]; then
  HAS_ISSUES=true
  echo "DOC STANDARDS: $FILE_PATH" >&2
  [ -n "$ERRORS" ] && echo -e "Errors (must fix):\n$ERRORS" >&2
  [ -n "$WARNINGS" ] && echo -e "Warnings (should fix):\n$WARNINGS" >&2
  [ -n "$SUGGESTIONS" ] && echo -e "Suggestions:\n$SUGGESTIONS" >&2
fi

if [ "$HAS_ISSUES" = true ]; then
  HOOK_DECISION="warn"
  HOOK_REASON="doc standards: $BASENAME"
  record_hook_outcome "doc-manager" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 1
fi

hook_log "doc validation passed: $BASENAME"
record_hook_outcome "doc-manager" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
