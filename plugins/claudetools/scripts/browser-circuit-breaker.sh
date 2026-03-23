#!/usr/bin/env bash
# PostToolUse hook — circuit breaker for browser automation spirals
# Detects two anti-patterns:
#   1. 10+ browser MCP calls in 5 minutes (tool-call flooding)
#   2. 5+ consecutive browser calls that returned errors (page is broken)
# Fires on all PostToolUse events; exits 0 immediately for non-browser tools.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Extract tool name — bail immediately if not a browser tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL_NAME" in
  mcp__claude-in-chrome__*) ;;  # continue
  *) exit 0 ;;
esac

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

hook_log "invoked tool=$TOOL_NAME"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

HOOK_DECISION="allow"
HOOK_REASON=""

# Session-scoped tracking file (JSONL — one record per browser call)
CALL_LOG=$(session_tmp_path "browser-calls")

# Determine if this call had an error
HAS_ERROR="false"
ERROR_TEXT=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null || true)
if [ -n "$ERROR_TEXT" ]; then
  HAS_ERROR="true"
else
  # Check tool_response for error indicators
  RESPONSE_TEXT=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null || true)
  if [ -n "$RESPONSE_TEXT" ]; then
    # Only count explicit error signals, not informational stderr
    if echo "$RESPONSE_TEXT" | grep -qiE 'error|exception|failed|timeout|refused|ERR_'; then
      HAS_ERROR="true"
    fi
  fi
fi

# Record this call
NOW=$(date +%s)
printf '{"ts":%d,"tool":"%s","error":%s}\n' "$NOW" "$TOOL_NAME" "$HAS_ERROR" >> "$CALL_LOG" 2>/dev/null || true

# --- Check 1: Total browser calls in the last 5 minutes ---
WINDOW_START=$((NOW - 300))
RECENT_COUNT=0
if [ -f "$CALL_LOG" ]; then
  RECENT_COUNT=$(awk -F'"ts":' -v cutoff="$WINDOW_START" '
    NF >= 2 {
      split($2, a, /[^0-9]/);
      if (a[1]+0 >= cutoff) count++
    }
    END { print count+0 }
  ' "$CALL_LOG")
fi

if [ "$RECENT_COUNT" -ge 10 ]; then
  HOOK_DECISION="block"
  HOOK_REASON="browser_call_flood count=$RECENT_COUNT"
  echo "BROWSER AUTOMATION CIRCUIT BREAKER: ${RECENT_COUNT} browser automation calls in 5 minutes." >&2
  echo "Stop and reconsider your approach — if the same page/element isn't working, the issue is likely upstream (SSR, hydration, deployment). Try a different verification method." >&2
  exit 1
fi

# --- Check 2: Consecutive browser calls with errors ---
CONSECUTIVE_ERRORS=0
if [ -f "$CALL_LOG" ]; then
  # Read the last N lines and count trailing consecutive errors
  CONSECUTIVE_ERRORS=$(tail -n 20 "$CALL_LOG" | tac | awk '
    /\"error\":true/ { count++; next }
    { exit }
    END { print count+0 }
  ')
fi

if [ "$CONSECUTIVE_ERRORS" -ge 5 ]; then
  HOOK_DECISION="block"
  HOOK_REASON="consecutive_browser_errors count=$CONSECUTIVE_ERRORS"
  echo "BROWSER AUTOMATION CIRCUIT BREAKER: ${CONSECUTIVE_ERRORS} consecutive browser errors." >&2
  echo "The page may have a fundamental issue. Stop browser testing and diagnose the root cause." >&2
  exit 1
fi

hook_log "allow recent=$RECENT_COUNT consecutive_errors=$CONSECUTIVE_ERRORS"
exit 0
