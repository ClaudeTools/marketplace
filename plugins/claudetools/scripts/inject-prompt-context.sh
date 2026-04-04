#!/bin/bash
# inject-prompt-context.sh — UserPromptSubmit hook
# Minimal context injection. Only outputs when there's something actionable.
# Everything here costs context tokens — keep it SHORT.

INPUT=$(cat)

# --- Single extraction of all needed fields (one jq fork instead of four) ---
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "")",
  @sh "CWD=\(.cwd // ".")",
  @sh "USER_TEXT=\(
    if (.content | type) == "array" then
      [.content[] | if type == "string" then . elif .type == "text" then .text else "" end] | join(" ")
    elif (.content | type) == "string" then .content
    else ""
    end
  )"
' 2>/dev/null)" || { SESSION_ID=""; CWD="."; USER_TEXT=""; }
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"
STOP_FLAG="/tmp/claude-user-stop-${SESSION_ID}"

# --- User STOP detection ---
if echo "$USER_TEXT" | grep -qiE '^\s*(stop|STOP|stop it|i said stop|can you stop|please stop|fucking stop|just stop)\s*[.!?]*\s*$'; then
  touch "$STOP_FLAG"
  echo "User requested STOP. All tool calls are blocked until you receive a new non-stop instruction." >&2
  exit 0
fi

# If user sends a non-stop message, clear the flag
if [[ -f "$STOP_FLAG" ]] && [[ -n "$USER_TEXT" ]]; then
  rm -f "$STOP_FLAG"
fi

# --- Skill intent classification (Tier 1: deterministic) ---
source "$(dirname "$0")/lib/skill-router.sh"

MATCHED_CMD=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_CMD" ]; then
  # Only inject workflow context once per session per command
  SKILL_FLAG="/tmp/.claude-workflow-injected-${MATCHED_CMD}-${SESSION_ID}"
  if [ ! -f "$SKILL_FLAG" ]; then
    WORKFLOW_CTX=$(format_workflow_context "$MATCHED_CMD")
    echo "$WORKFLOW_CTX"
    touch "$SKILL_FLAG"
  fi
  # Always track the invocation for analytics
  source "$(dirname "$0")/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_CMD" "$SESSION_ID" "keyword" 2>/dev/null || true
fi

# --- Phase-aware context (Tier 1: deterministic) ---
# Only inject when the phase actually changes — avoids re-injecting identical text
# on every user message (a flag file per phase+session acts as the gate).
source "$(dirname "$0")/lib/phase-detect.sh"
CURRENT_PHASE=$(detect_phase "$CWD" "$SESSION_ID" 2>/dev/null || true)
if [ -n "$CURRENT_PHASE" ] && [ "$CURRENT_PHASE" != "unknown" ]; then
  PHASE_FLAG="/tmp/.claude-phase-${CURRENT_PHASE}-${SESSION_ID}"
  if [ ! -f "$PHASE_FLAG" ]; then
    # Clear other phase flags for this session before setting the new one
    rm -f "/tmp/.claude-phase-"*"-${SESSION_ID}" 2>/dev/null || true
    PHASE_CTX=$(format_phase_context "$CURRENT_PHASE")
    if [ -n "$PHASE_CTX" ]; then
      echo "$PHASE_CTX"
      touch "$PHASE_FLAG"
    fi
  fi
fi

exit 0
