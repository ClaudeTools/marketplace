#!/bin/bash
# PermissionRequest hook — auto-approves safe read-only operations
# to reduce permission dialog fatigue. Exit 0 always.
# Outputs allow JSON for safe ops, empty output to defer to default handling.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/thresholds.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-defer}" "${HOOK_REASON:-}"' EXIT

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

ALLOW_JSON='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'

approve() {
  HOOK_DECISION="allow" HOOK_REASON="$1"
  record_hook_outcome "auto-approve-safe" "PermissionRequest" "allow" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
  echo "$ALLOW_JSON"
  exit 0
}

# --- Always-safe tools ---
case "$TOOL_NAME" in
  Read|Glob|Grep)
    approve "safe tool: $TOOL_NAME"
    ;;
esac

# --- Bash command analysis ---
if [ "$TOOL_NAME" != "Bash" ] || [ -z "$COMMAND" ]; then
  exit 0
fi

# Split command into segments on pipes, semicolons, &&, ||
# Check every segment for dangerous commands first
SEGMENTS=$(echo "$COMMAND" | sed 's/[|;]/\n/g; s/&&/\n/g; s/||/\n/g')

DANGEROUS_PATTERN='(^|[[:space:]])(rm|chmod|chown|kill|dd|mkfs|shutdown|reboot|curl|wget)(([[:space:]])|$)'
NPM_DANGEROUS='(^|[[:space:]])(npm[[:space:]]+(install|publish))(([[:space:]])|$)'
PIP_DANGEROUS='(^|[[:space:]])(pip3?[[:space:]]+install)(([[:space:]])|$)'

while IFS= read -r segment; do
  segment=$(echo "$segment" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [ -z "$segment" ] && continue

  if echo "$segment" | grep -qE "$DANGEROUS_PATTERN"; then
    HOOK_DECISION="defer" HOOK_REASON="dangerous command in segment: $segment"
    exit 0
  fi
  if echo "$segment" | grep -qE "$NPM_DANGEROUS"; then
    HOOK_DECISION="defer" HOOK_REASON="dangerous npm command in segment: $segment"
    exit 0
  fi
  if echo "$segment" | grep -qE "$PIP_DANGEROUS"; then
    HOOK_DECISION="defer" HOOK_REASON="dangerous pip command in segment: $segment"
    exit 0
  fi
done <<< "$SEGMENTS"

# No dangerous segments found — check if leading command is safe
LEADING=$(echo "$COMMAND" | sed 's/[|;].*//' | sed 's/&&.*//' | sed 's/||.*//' | sed 's/^[[:space:]]*//')

# Safe file inspection commands
if echo "$LEADING" | grep -qE '^(ls|cat|head|tail|wc|find|grep|rg|tree|pwd|echo|date|which|file|stat|du|df)([[:space:]]|$)'; then
  approve "safe file inspection: $LEADING"
fi

# Git read-only commands
if echo "$LEADING" | grep -qE '^git[[:space:]]+(log|diff|status|branch|show|rev-parse|remote|tag)([[:space:]]|$)'; then
  approve "safe git read: $LEADING"
fi

# Node test/lint/check commands
if echo "$LEADING" | grep -qE '^npm[[:space:]]+(test|run[[:space:]]+(test|lint|typecheck|build))([[:space:]]|$)'; then
  approve "safe npm command: $LEADING"
fi
if echo "$LEADING" | grep -qE '^npx[[:space:]]+(tsc|prettier|eslint|jest|vitest)([[:space:]]|$)'; then
  approve "safe npx command: $LEADING"
fi

# Python test/lint commands
if echo "$LEADING" | grep -qE '^(pytest|mypy|pyright|ruff|flake8|pylint)([[:space:]]|$)'; then
  approve "safe python tool: $LEADING"
fi
if echo "$LEADING" | grep -qE '^python3?[[:space:]]+-m[[:space:]]+(pytest)([[:space:]]|$)'; then
  approve "safe python -m: $LEADING"
fi
if echo "$LEADING" | grep -qE '^black[[:space:]]+--check([[:space:]]|$)'; then
  approve "safe black --check: $LEADING"
fi

# Rust commands
if echo "$LEADING" | grep -qE '^cargo[[:space:]]+(test|check|clippy|build|fmt)([[:space:]]|$)'; then
  approve "safe cargo command: $LEADING"
fi

# Go commands
if echo "$LEADING" | grep -qE '^go[[:space:]]+(test|vet|build|fmt)([[:space:]]|$)'; then
  approve "safe go command: $LEADING"
fi

# Ruby commands
if echo "$LEADING" | grep -qE '^(bundle[[:space:]]+exec[[:space:]]+rspec|rubocop)([[:space:]]|$)'; then
  approve "safe ruby command: $LEADING"
fi

# Java commands
if echo "$LEADING" | grep -qE '^(mvn|gradle)[[:space:]]+test([[:space:]]|$)'; then
  approve "safe java command: $LEADING"
fi

# C# commands
if echo "$LEADING" | grep -qE '^dotnet[[:space:]]+(test|build)([[:space:]]|$)'; then
  approve "safe dotnet command: $LEADING"
fi

# Swift commands
if echo "$LEADING" | grep -qE '^swift[[:space:]]+(test|build)([[:space:]]|$)'; then
  approve "safe swift command: $LEADING"
fi

# Not matched — defer to default permission handling
record_hook_outcome "auto-approve-safe" "PermissionRequest" "pass" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
exit 0
