#!/bin/bash
# PreToolUse hook for Edit — deterministic replacement for the AI bulk-operation gate
# Detects mechanical find-and-replace operations that should use sed/grep instead
# Exit 0 = allow, Exit 0 + block JSON = reject
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract Edit parameters
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null || true)
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null || true)

# Skip if no old_string (Write tool, not Edit)
[ -z "$OLD_STRING" ] && exit 0
# Skip if file doesn't exist
[ -f "$FILE_PATH" ] || exit 0

# --- Check 1: replace_all with many occurrences → suggest sed ---
if [ "$REPLACE_ALL" = "true" ]; then
  # Escape old_string for grep
  ESCAPED=$(printf '%s\n' "$OLD_STRING" | sed 's/[[\.*^$/]/\\&/g' | head -1)
  COUNT=$(grep -cF "$OLD_STRING" "$FILE_PATH" 2>/dev/null || echo 0)

  if [ "$COUNT" -ge 5 ]; then
    REASON="Bulk replace_all with ${COUNT} occurrences. Use Bash with sed instead: sed -i 's/OLD/NEW/g' \"$FILE_PATH\" — deterministic tools are faster and more reliable for mechanical operations."
    HOOK_DECISION="block" HOOK_REASON="bulk replace_all (${COUNT} occurrences)"
    jq -n --arg reason "$REASON" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "block",
        "permissionDecisionReason": $reason
      }
    }'
    exit 0
  fi
fi

# --- Check 2: old_string is a single short token appearing many times → rename via sed ---
OLD_LINE_COUNT=$(echo "$OLD_STRING" | wc -l)
if [ "$OLD_LINE_COUNT" -le 2 ]; then
  # Single-line old_string — check if it's a variable/component rename
  OLD_TRIMMED=$(echo "$OLD_STRING" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  NEW_TRIMMED=$(echo "$NEW_STRING" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # If old and new differ only in the identifier name (same structure), it's a rename
  OLD_TOKENS=$(echo "$OLD_TRIMMED" | tr -cs '[:alnum:]_' '\n' | sort -u | wc -l)
  NEW_TOKENS=$(echo "$NEW_TRIMMED" | tr -cs '[:alnum:]_' '\n' | sort -u | wc -l)

  if [ "$OLD_TOKENS" -le 3 ] && [ "$NEW_TOKENS" -le 3 ]; then
    COUNT=$(grep -cF "$OLD_TRIMMED" "$FILE_PATH" 2>/dev/null || echo 0)
    if [ "$COUNT" -ge 8 ]; then
      REASON="This looks like a rename operation (${COUNT} occurrences of '${OLD_TRIMMED:0:40}'). Use Bash with sed for bulk renames — deterministic tools over AI inference for mechanical operations."
      HOOK_DECISION="block" HOOK_REASON="bulk rename (${COUNT} occurrences)"
      jq -n --arg reason "$REASON" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "block",
          "permissionDecisionReason": $reason
        }
      }'
      exit 0
    fi
  fi
fi

# --- Check 3: old_string is purely whitespace/formatting → use formatter ---
if echo "$OLD_STRING" | grep -qE '^[[:space:]]+$' && echo "$NEW_STRING" | grep -qE '^[[:space:]]+$'; then
  REASON="Whitespace-only change detected. Use a formatter (prettier, eslint --fix) or sed for whitespace adjustments — deterministic tools over AI inference."
  HOOK_DECISION="block" HOOK_REASON="whitespace-only formatting change"
  jq -n --arg reason "$REASON" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
fi

# --- Check 4: old_string is all import lines → use formatter ---
IMPORT_LINES=$(echo "$OLD_STRING" | grep -cE '^\s*(import|from|require)' 2>/dev/null || echo 0)
TOTAL_LINES=$(echo "$OLD_STRING" | wc -l)
if [ "$TOTAL_LINES" -ge 8 ] && [ "$IMPORT_LINES" -ge "$((TOTAL_LINES * 7 / 10))" ]; then
  REASON="Import reorganization detected (${IMPORT_LINES}/${TOTAL_LINES} lines are imports). Use eslint --fix with import-sorting rules or a formatter — deterministic tools over AI inference."
  HOOK_DECISION="block" HOOK_REASON="import reorganization"
  jq -n --arg reason "$REASON" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
fi

exit 0
