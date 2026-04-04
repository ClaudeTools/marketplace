#!/bin/bash
# Validator: unasked dependency detection
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Returns: 0 = clean, 1 = unasked deps found (warning)

validate_unasked_deps() {
  # Extract the bash command that was executed
  local COMMAND
  COMMAND=$(hook_get_field '.tool_input.command')

  if [ -z "$COMMAND" ]; then
    return 0
  fi

  # Detect package installation commands and extract package names
  local PACKAGES=""
  local PKG_MANAGER=""

  # npm/yarn/pnpm install
  if echo "$COMMAND" | grep -qE '(npm|yarn|pnpm)\s+(install|add|i)\s' 2>/dev/null; then
    PKG_MANAGER="npm"
    PACKAGES=$(echo "$COMMAND" | grep -oE '(npm|yarn|pnpm)\s+(install|add|i)\s+(.+)' | sed -E 's/(npm|yarn|pnpm)\s+(install|add|i)\s+//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' || true)
  fi

  # pip install
  if echo "$COMMAND" | grep -qE '(pip|pip3|uv pip)\s+install\s' 2>/dev/null; then
    PKG_MANAGER="pip"
    PACKAGES=$(echo "$COMMAND" | grep -oE '(pip|pip3|uv pip)\s+install\s+(.+)' | sed -E 's/(pip|pip3|uv pip)\s+install\s+//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' || true)
  fi

  # cargo add
  if echo "$COMMAND" | grep -qE 'cargo\s+add\s' 2>/dev/null; then
    PKG_MANAGER="cargo"
    PACKAGES=$(echo "$COMMAND" | grep -oE 'cargo\s+add\s+(.+)' | sed 's/cargo\s+add\s+//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' || true)
  fi

  # go get
  if echo "$COMMAND" | grep -qE 'go\s+get\s' 2>/dev/null; then
    PKG_MANAGER="go"
    PACKAGES=$(echo "$COMMAND" | grep -oE 'go\s+get\s+(.+)' | sed 's/go\s+get\s+//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' || true)
  fi

  if [ -z "$PACKAGES" ]; then
    return 0
  fi

  # Check if the active task mentions these packages
  local TASK_DIR="$HOME/.claude/tasks"
  local TASK_TEXT=""

  if [ -d "$TASK_DIR" ]; then
    while IFS= read -r task_file; do
      [ -f "$task_file" ] || continue
      local STATUS
      STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
      [ "$STATUS" != "in_progress" ] && continue

      local SUBJECT DESCRIPTION
      SUBJECT=$(jq -r '.subject // empty' "$task_file" 2>/dev/null || true)
      DESCRIPTION=$(jq -r '.description // empty' "$task_file" 2>/dev/null || true)
      TASK_TEXT="$SUBJECT $DESCRIPTION"
      break
    done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
  fi

  # Check which packages are not mentioned in the task
  local UNASKED=""
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    # Strip version specifiers for comparison
    local PKG_NAME
    PKG_NAME=$(echo "$pkg" | sed -E 's/@[^/]+$//; s/[>=<~^].*//')
    if [ -n "$TASK_TEXT" ]; then
      if ! echo "$TASK_TEXT" | grep -qi "$PKG_NAME" 2>/dev/null; then
        UNASKED="${UNASKED}${pkg}\n"
      fi
    else
      # No task context — flag all installs as potentially unasked
      UNASKED="${UNASKED}${pkg}\n"
    fi
  done <<< "$PACKAGES"

  if [ -z "$UNASKED" ]; then
    record_hook_outcome "detect-unasked-deps" "PostToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
    return 0
  fi

  # Warn about unasked dependencies
  local PKG_LIST
  PKG_LIST=$(echo -e "$UNASKED" | sed '/^$/d' | head -10 | tr '\n' ', ' | sed 's/,$//')
  local WARNING="New dependency installed via ${PKG_MANAGER}: ${PKG_LIST}. Verify this dependency is needed for the current task. Models sometimes add familiar frameworks (flask, express) even when simpler alternatives exist or when the task calls for stdlib-only solutions."

  record_hook_outcome "detect-unasked-deps" "PostToolUse" "warn" "Bash" "" "" "$MODEL_FAMILY"

  echo "$WARNING"
  return 1
}
