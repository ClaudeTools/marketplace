#!/bin/bash
# PostToolUse:Bash hook — detects when models install new dependencies without being asked
# Training-derived: models default to familiar frameworks (flask, express) regardless of constraints
# Domain-agnostic: works for npm, pip, cargo, go, composer
#
# Warns when package install commands add packages not mentioned in the task description
# Exit 1 = warning injected, Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the bash command that was executed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Detect package installation commands and extract package names
PACKAGES=""
PKG_MANAGER=""

# npm/yarn/pnpm install
if echo "$COMMAND" | grep -qE '(npm|yarn|pnpm)\s+(install|add|i)\s' 2>/dev/null; then
  PKG_MANAGER="npm"
  # Extract package names (skip flags like --save-dev, -D, etc.)
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
  exit 0
fi

# Check if the active task mentions these packages
TASK_DIR="$HOME/.claude/tasks"
TASK_TEXT=""

if [ -d "$TASK_DIR" ]; then
  while IFS= read -r task_file; do
    [ -f "$task_file" ] || continue
    STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
    [ "$STATUS" != "in_progress" ] && continue

    SUBJECT=$(jq -r '.subject // empty' "$task_file" 2>/dev/null || true)
    DESCRIPTION=$(jq -r '.description // empty' "$task_file" 2>/dev/null || true)
    TASK_TEXT="$SUBJECT $DESCRIPTION"
    break
  done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
fi

# Check which packages are not mentioned in the task
UNASKED=""
while IFS= read -r pkg; do
  [ -z "$pkg" ] && continue
  # Strip version specifiers for comparison
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
  exit 0
fi

# Warn about unasked dependencies
PKG_LIST=$(echo -e "$UNASKED" | sed '/^$/d' | head -10 | tr '\n' ', ' | sed 's/,$//')
WARNING="New dependency installed via ${PKG_MANAGER}: ${PKG_LIST}. Verify this dependency is needed for the current task. Models sometimes add familiar frameworks (flask, express) even when simpler alternatives exist or when the task calls for stdlib-only solutions."

HOOK_DECISION="warn"; HOOK_REASON="$WARNING"
record_hook_outcome "detect-unasked-deps" "PostToolUse" "warn" "Bash" "" "" "$MODEL_FAMILY"

echo "$WARNING"
exit 1
