#!/bin/bash
# Validator: warn when Write tool overwrites existing files with meaningful content
# Nudges agents to use Edit for targeted changes instead of full-file rewrites.
# Agnostic — applies to any file type.
# Returns: 0 = pass (new file or small file), 1 = warn (use Edit instead)

validate_prefer_edit_over_write() {
  local TOOL_NAME
  TOOL_NAME=$(hook_get_field '.tool_name')
  # Only check Write tool — Edit is already targeted
  [[ "$TOOL_NAME" != "Write" ]] && return 0

  local FILE_PATH
  FILE_PATH=$(hook_get_field '.tool_input.file_path')
  [ -z "$FILE_PATH" ] && return 0

  # If file doesn't exist, this is creating a new file — allow
  [ ! -f "$FILE_PATH" ] && return 0

  # Skip generated/build files that are legitimately overwritten
  case "$FILE_PATH" in
    */dist/*|*/build/*|*/node_modules/*|*/.next/*|*/coverage/*|*.lock|*.map) return 0 ;;
    */logs/*|*.log|*.jsonl) return 0 ;;
  esac

  # Count existing file lines
  local EXISTING_LINES
  EXISTING_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")
  EXISTING_LINES=${EXISTING_LINES// /}

  # Small files (<50 lines) — Write is fine, Edit overhead not worth it
  [ "$EXISTING_LINES" -lt 50 ] && return 0

  local BASENAME
  BASENAME=$(basename "$FILE_PATH")

  echo "Overwriting '${BASENAME}' (${EXISTING_LINES} lines) with Write tool. Use Edit for targeted changes instead — it preserves the original structure and only modifies what needs to change." >&2
  emit_event "prefer-edit-over-write" "overwrite_warned" "warn" "0" "{\"lines\":${EXISTING_LINES}}" 2>/dev/null || true
  record_hook_outcome "prefer-edit-over-write" "PreToolUse" "warn" "Write" "" "" "${MODEL_FAMILY:-unknown}"
  return 1
}
