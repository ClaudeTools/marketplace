#!/bin/bash
# PreToolUse:Edit|Write hook — warns when file modifications fall outside task scope
# Training-derived: 20% of model executions create files outside defined scope
# Domain-agnostic: works for any project by inferring scope from task descriptions
#
# Scope inference rules:
# 1. If task description contains file paths/globs → those define scope
# 2. If task mentions specific directories (src/, tests/, etc.) → those are scope
# 3. If no scope hints → allow everything (don't block on ambiguous tasks)
#
# Exit 0 always — uses JSON stdout for blocking/warning

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract file path being edited/written
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip config/meta files — these are always in scope
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.csv)
    exit 0
    ;;
  */.claude/*|*/.git/*|*/node_modules/*|*/.venv/*|*/venv/*)
    exit 0
    ;;
esac

# Find active in_progress task and extract scope hints
TASK_DIR="$HOME/.claude/tasks"
TASK_SCOPE=""
TASK_SUBJECT=""

if [ -d "$TASK_DIR" ]; then
  while IFS= read -r task_file; do
    [ -f "$task_file" ] || continue
    STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
    [ "$STATUS" != "in_progress" ] && continue

    TASK_SUBJECT=$(jq -r '.subject // empty' "$task_file" 2>/dev/null || true)
    DESCRIPTION=$(jq -r '.description // empty' "$task_file" 2>/dev/null || true)
    COMBINED="$TASK_SUBJECT $DESCRIPTION"

    # Extract explicit directory scope from task description
    # Look for patterns like "in src/", "modify src/routes/", "only touch tests/"
    # Also look for "files_in_scope" or explicit path mentions
    SCOPE_DIRS=$(echo "$COMBINED" | grep -oE '(src|lib|tests|test|app|pages|components|routes|scripts|config|public|client|server|api|utils|helpers|services|models|controllers|views|hooks|styles|assets)/[^ ]*' | sed 's|/[^/]*$||' | sort -u || true)

    # Also extract top-level directory mentions like "only modify src/"
    TOP_DIRS=$(echo "$COMBINED" | grep -oE '\b(src|lib|tests|test|app|pages|components|routes|scripts|config|public|client|server|api|plugin)/\b' | sort -u || true)

    TASK_SCOPE=$(printf '%s\n%s' "$SCOPE_DIRS" "$TOP_DIRS" | sed '/^$/d' | sort -u)
    break
  done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
fi

# No active task or no scope hints → allow
if [ -z "$TASK_SCOPE" ]; then
  exit 0
fi

# Check if the file path falls within any scoped directory
FILE_DIR=$(dirname "$FILE_PATH")
IN_SCOPE=false

while IFS= read -r scope_dir; do
  [ -z "$scope_dir" ] && continue
  # Check if file path starts with or contains the scope directory
  if echo "$FILE_PATH" | grep -q "^${scope_dir}\|/${scope_dir}" 2>/dev/null; then
    IN_SCOPE=true
    break
  fi
  # Also check if the file is in a subdirectory of scope
  if echo "$FILE_DIR" | grep -q "^${scope_dir}\|/${scope_dir}" 2>/dev/null; then
    IN_SCOPE=true
    break
  fi
done <<< "$TASK_SCOPE"

if [ "$IN_SCOPE" = true ]; then
  record_hook_outcome "enforce-task-scope" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
  exit 0
fi

# File is outside scope — warn (not block, since scope inference is heuristic)
BASENAME=$(basename "$FILE_PATH")
WARNING="File '${BASENAME}' appears outside the task scope. Task '${TASK_SUBJECT}' seems scoped to: $(echo "$TASK_SCOPE" | tr '\n' ', ' | sed 's/,$//'). If this file change is needed, continue. If not, focus on files within scope."

HOOK_DECISION="warn"; HOOK_REASON="$WARNING"
record_hook_outcome "enforce-task-scope" "PreToolUse" "warn" "" "" "" "$MODEL_FAMILY"

# Emit as warning (exit 1), not hard block — scope inference is heuristic
echo "$WARNING"
exit 1
