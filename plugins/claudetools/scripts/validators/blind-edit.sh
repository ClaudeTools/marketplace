#!/bin/bash
# Validator: detect edits to files never read in this session
# Sourced by the pre-edit-gate dispatcher after hook_init() has been called.
# Globals used: INPUT, FILE_PATH, FILE_EXT, MODEL_FAMILY
# Returns: 0 = file was read or exempt, 1 = warn (blind edit detected)

validate_blind_edit() {
  # Skip if no file path
  [ -z "$FILE_PATH" ] && return 0

  # Skip for new files (Write creating a file that doesn't exist yet)
  [ ! -f "$FILE_PATH" ] && return 0

  # Skip non-code files: docs, config, lock files, generated output
  case "$FILE_EXT" in
    md|txt|rst|json|yaml|yml|toml|ini|cfg|lock|svg|png|jpg|gif|csv) return 0 ;;
  esac

  # Skip plugin/IDE config paths
  case "$FILE_PATH" in
    */.claude/*|*/.github/*|*/.vscode/*|*/.idea/*|*/node_modules/*) return 0 ;;
  esac

  # Skip test files — lower risk for blind edits
  case "$FILE_PATH" in
    *.test.*|*.spec.*|*__tests__/*|*__mocks__/*|*.stories.*) return 0 ;;
  esac

  # Find session reads tracking file
  local SESSION_ID
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -z "$SESSION_ID" ] && SESSION_ID="$PPID"

  local READS_FILE="/tmp/codebase-pilot-reads-${SESSION_ID}.jsonl"

  # If no tracking file exists, this is early in the session — allow
  [ ! -f "$READS_FILE" ] && return 0

  # Check if this file was read (exact path match)
  if grep -qF "\"$FILE_PATH\"" "$READS_FILE" 2>/dev/null; then
    # File was read or edited — check it was actually a read event
    if jq -e --arg p "$FILE_PATH" 'select(.path == $p and (.event == "read" or .event == null))' "$READS_FILE" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Also check session-ids file for cross-session reads (continued sessions)
  local PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
  local SESSION_IDS_FILE="$PROJECT_ROOT/.codeindex/session-ids"
  if [ -f "$SESSION_IDS_FILE" ]; then
    while IFS= read -r sid; do
      [ -z "$sid" ] && continue
      [ "$sid" = "$SESSION_ID" ] && continue
      local OTHER_READS="/tmp/codebase-pilot-reads-${sid}.jsonl"
      [ -f "$OTHER_READS" ] || continue
      if grep -qF "\"$FILE_PATH\"" "$OTHER_READS" 2>/dev/null; then
        return 0
      fi
    done < "$SESSION_IDS_FILE"
  fi

  local BASENAME
  BASENAME=$(basename "$FILE_PATH")
  echo "Editing '$BASENAME' without reading it first. Read the file (or the relevant section) before modifying it — blind edits cause bugs." >&2
  record_hook_outcome "blind-edit-guard" "PreToolUse" "warn" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
  return 1
}
