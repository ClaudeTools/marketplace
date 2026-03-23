#!/bin/bash
# PreToolUse:Bash — AI-powered evaluation of potentially destructive commands
# Fast path: regex pre-filter exits immediately for safe commands
# Slow path: calls Claude CLI (haiku) for pattern-matching commands
# Degrades gracefully: if claude CLI missing or timeout, allows the command
# Exit 0 always. JSON stdout with "block" to deny.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$CMD" ]; then
  exit 0
fi

# --- Fast path: regex pre-filter ---
# Only invoke AI for commands that match known destructive patterns.
# All other commands exit immediately (zero overhead).
if ! echo "$CMD" | grep -qE '(\brm\b|\brmdir\b|git\s+(checkout|reset|rebase|stash|branch\s+-D)|docker\s+(prune|rm\b)|DROP\s+TABLE|DELETE\s+FROM|\bkill\b|\bpkill\b|\bdd\b|\bmkfs\b|>\s*/dev/)'; then
  exit 0
fi

# --- Slow path: AI evaluation ---
# Command matched a destructive pattern — ask AI to evaluate safety

# Check if claude CLI is available
if ! command -v claude &>/dev/null; then
  hook_log "claude CLI not available, allowing"
  exit 0
fi

PROMPT="You are a command safety evaluator. Evaluate this bash command for safety.

Command: ${CMD}

Safety principles:
1. Prefer safer alternatives (git stash over git checkout ., trash over rm -rf)
2. Investigate before deleting (ls/find before rm, git log before reset)
3. When in doubt, ask the user rather than allowing a destructive operation

Respond with EXACTLY one word on the first line:
- SAFE — if the command is reasonable and targeted (e.g., rm of a specific temp file, git checkout of a single file)
- UNSAFE — if the command is broadly destructive, irreversible, or affects critical data without a clear safe target

Then on the second line, a brief reason (10 words max)."

RESULT=$(echo "$PROMPT" | timeout 10 claude -p --no-input --model haiku 2>/dev/null || echo "TIMEOUT")

# Degrade gracefully on timeout or CLI error
case "$RESULT" in
  TIMEOUT|"")
    hook_log "AI safety check timed out or failed, allowing"
    exit 0
    ;;
esac

VERDICT=$(echo "$RESULT" | head -1 | tr -d '[:space:]')
REASON=$(echo "$RESULT" | sed -n '2p' | head -c 100)

case "$VERDICT" in
  SAFE)
    hook_log "AI safety: SAFE — $REASON"
    exit 0
    ;;
  UNSAFE)
    hook_log "AI safety: UNSAFE — $REASON"
    HOOK_DECISION="block" HOOK_REASON="AI safety: $REASON"
    jq -n \
      --arg reason "AI safety check: ${REASON:-Command flagged as potentially destructive. Use a safer alternative or confirm with the user.}" \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "block",
          "permissionDecisionReason": $reason
        }
      }'
    exit 0
    ;;
  *)
    # Unexpected response — allow (degrade gracefully)
    hook_log "AI safety: unexpected verdict '$VERDICT', allowing"
    exit 0
    ;;
esac
