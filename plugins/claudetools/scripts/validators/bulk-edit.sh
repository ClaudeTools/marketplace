#!/bin/bash
# Validator: detect-bulk-edit
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, FILE_PATH
# Calls: hook_get_field for tool_name and tool_input fields
# Returns: 0 = clean, 2 = bulk operation detected (block)
# Output: block message written to stdout

validate_bulk_edit() {
  local TOOL_NAME
  TOOL_NAME=$(hook_get_field '.tool_name')
  [[ "$TOOL_NAME" != "Edit" ]] && return 0

  # Extract Edit parameters
  local OLD_STRING NEW_STRING REPLACE_ALL
  OLD_STRING=$(hook_get_field '.tool_input.old_string')
  NEW_STRING=$(hook_get_field '.tool_input.new_string')
  REPLACE_ALL=$(hook_get_field '.tool_input.replace_all')

  # Skip if no old_string (Write tool, not Edit)
  [ -z "$OLD_STRING" ] && return 0
  # Skip if file doesn't exist
  [ -f "$FILE_PATH" ] || return 0

  # --- Check 1: replace_all with many occurrences → suggest sed ---
  if [ "$REPLACE_ALL" = "true" ]; then
    local COUNT
    COUNT=$(grep -cF "$OLD_STRING" "$FILE_PATH" 2>/dev/null || echo 0)

    if [ "$COUNT" -ge 5 ]; then
      local REASON="Bulk replace_all with ${COUNT} occurrences. Use Bash with sed instead: sed -i 's/OLD/NEW/g' \"$FILE_PATH\" — deterministic tools are faster and more reliable for mechanical operations."
      echo "$REASON"
      return 2
    fi
  fi

  # --- Check 2: old_string is a single short token appearing many times → rename via sed ---
  local OLD_LINE_COUNT
  OLD_LINE_COUNT=$(echo "$OLD_STRING" | wc -l)
  if [ "$OLD_LINE_COUNT" -le 2 ]; then
    # Single-line old_string — check if it's a variable/component rename
    local OLD_TRIMMED NEW_TRIMMED
    OLD_TRIMMED=$(echo "$OLD_STRING" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    NEW_TRIMMED=$(echo "$NEW_STRING" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # If old and new differ only in the identifier name (same structure), it's a rename
    local OLD_TOKENS NEW_TOKENS
    OLD_TOKENS=$(echo "$OLD_TRIMMED" | tr -cs '[:alnum:]_' '\n' | sort -u | wc -l)
    NEW_TOKENS=$(echo "$NEW_TRIMMED" | tr -cs '[:alnum:]_' '\n' | sort -u | wc -l)

    if [ "$OLD_TOKENS" -le 3 ] && [ "$NEW_TOKENS" -le 3 ]; then
      local COUNT
      COUNT=$(grep -cF "$OLD_TRIMMED" "$FILE_PATH" 2>/dev/null || echo 0)
      if [ "$COUNT" -ge 8 ]; then
        local REASON="This looks like a rename operation (${COUNT} occurrences of '${OLD_TRIMMED:0:40}'). Use Bash with sed for bulk renames — deterministic tools over AI inference for mechanical operations."
        echo "$REASON"
        return 2
      fi
    fi
  fi

  # --- Check 3: old_string is purely whitespace/formatting → use formatter ---
  if echo "$OLD_STRING" | grep -qE '^[[:space:]]+$' && echo "$NEW_STRING" | grep -qE '^[[:space:]]+$'; then
    local REASON="Whitespace-only change detected. Use a formatter (prettier, eslint --fix) or sed for whitespace adjustments — deterministic tools over AI inference."
    echo "$REASON"
    return 2
  fi

  # --- Check 4: old_string is all import lines → use formatter ---
  local IMPORT_LINES TOTAL_LINES
  IMPORT_LINES=$(echo "$OLD_STRING" | grep -cE '^\s*(import|from|require)' 2>/dev/null || echo 0)
  TOTAL_LINES=$(echo "$OLD_STRING" | wc -l)
  if [ "$TOTAL_LINES" -ge 8 ] && [ "$IMPORT_LINES" -ge "$((TOTAL_LINES * 7 / 10))" ]; then
    local REASON="Import reorganization detected (${IMPORT_LINES}/${TOTAL_LINES} lines are imports). Use eslint --fix with import-sorting rules or a formatter — deterministic tools over AI inference."
    echo "$REASON"
    return 2
  fi

  return 0
}
