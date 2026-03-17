#!/bin/bash
# PreToolUse hook for Edit|Write — blocks stub/placeholder content BEFORE it's written
# Checks tool_input.new_string (Edit) or tool_input.content (Write)
# Exit 0 always. JSON output with "block" to deny.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the proposed content from Edit (new_string) or Write (content)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null || true)

if [ -z "$CONTENT" ]; then
  exit 0
fi

# Extract file path for context
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)

# Skip non-code files
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__*|*__mocks__*) exit 0 ;;
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock) exit 0 ;;
  *.config.*|*.rc) exit 0 ;;
esac

BLOCKED=""

# Stub throws
if echo "$CONTENT" | grep -qiE 'throw new Error\(.*(not implemented|todo|fixme|placeholder)'; then
  BLOCKED="Blocked: stub throw (not implemented/todo/placeholder)"
fi

# TODO/FIXME markers as the ONLY content (not in a real comment explaining context)
if [ -z "$BLOCKED" ] && echo "$CONTENT" | grep -qE '^\s*(//|#)\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s'; then
  BLOCKED="Blocked: TODO/FIXME/STUB marker — implement the feature or skip it"
fi

# NotImplementedError (Python)
if [ -z "$BLOCKED" ] && echo "$CONTENT" | grep -qE 'raise\s+NotImplementedError'; then
  BLOCKED="Blocked: NotImplementedError — implement fully or tell the user you can't"
fi

# Empty function bodies being written
if [ -z "$BLOCKED" ] && echo "$CONTENT" | grep -qE 'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}'; then
  BLOCKED="Blocked: empty function body — implement the function or don't create it"
fi

# Functions that only return hardcoded null/undefined/{}/[]
if [ -z "$BLOCKED" ] && echo "$CONTENT" | grep -qE 'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*return\s+(null|undefined|\{\}|\[\])\s*;?\s*\}'; then
  BLOCKED="Blocked: function returns hardcoded null/undefined/{}/ — implement real logic"
fi

# --- New dependency detection (training-informed) ---
# Training data: models add heavy frameworks even when user says "stdlib only"
# This is a SOFT warning, not a block — only fires for new projects (no existing package manager files)
# The actual enforcement happens via must_not_contain in chain definitions

if [ -n "$BLOCKED" ]; then
  HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
  record_hook_outcome "block-stub-writes" "PreToolUse" "block" "" "" "" "$MODEL_FAMILY"
  jq -n \
    --arg reason "$BLOCKED" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "block",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

record_hook_outcome "block-stub-writes" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
