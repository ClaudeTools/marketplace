#!/bin/bash
# PreToolUse:Agent hook — enforces TeamCreate for Agent tool calls when teams are enabled
# When CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1: blocks bare Agent calls, requires team_name/name/worktree
# When teams feature is off: allows Agent calls freely (with naming advisory)
# Exit 0 always — blocking done via JSON stdout with permissionDecision "block"

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract fields from tool_input
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // empty' 2>/dev/null || true)
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)

# Extract isolation mode and agent name
ISOLATION=$(echo "$INPUT" | jq -r '.tool_input.isolation // empty' 2>/dev/null || true)
AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null || true)

# ALLOW: solo research agents (read-only, no team coordination needed)
if [[ "$SUBAGENT_TYPE" == "Explore" || "$SUBAGENT_TYPE" == "Plan" ]]; then
  exit 0
fi

# --- Feature flag: if teams are not available, allow with advisory ---
TEAMS_ENABLED="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"
if [ "$TEAMS_ENABLED" != "1" ]; then
  hook_log "teams feature disabled — allowing without team requirement"
  if [ -z "$AGENT_NAME" ]; then
    echo '{"systemMessage":"Tip: naming your agents (name: \"descriptive-name\") improves coordination and audit trail readability."}'
  fi
  exit 0
fi

# ALLOW: teammate spawn (has team_name)
if [ -n "$TEAM_NAME" ]; then
  # Verify the team actually exists (TeamCreate was called first)
  TEAM_CONFIG="$HOME/.claude/teams/${TEAM_NAME}/config.json"
  if [ ! -f "$TEAM_CONFIG" ]; then
    BLOCKED="Team '${TEAM_NAME}' does not exist. Call TeamCreate first to create the team, then spawn teammates."
    HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
    jq -n --arg reason "$BLOCKED" '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "block", permissionDecisionReason: $reason } }'
    exit 0
  fi

  # Block if teammate has no name (unnamed agents can't be coordinated)
  if [ -z "$AGENT_NAME" ]; then
    BLOCKED="Teammate must have a name parameter for coordination. Add name: \"descriptive-name\" to the Agent tool call."
    HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
    jq -n --arg reason "$BLOCKED" '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "block", permissionDecisionReason: $reason } }'
    exit 0
  fi

  # Block if no worktree isolation
  if [ "$ISOLATION" != "worktree" ]; then
    BLOCKED="Teammate '${AGENT_NAME}' must use isolation: \"worktree\" to prevent file conflicts. Add isolation: \"worktree\" to the Agent tool call."
    HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
    jq -n --arg reason "$BLOCKED" '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "block", permissionDecisionReason: $reason } }'
    exit 0
  fi

  # Check tmux availability - provide actionable guidance
  TEAMMATE_MODE=$(jq -r '.teammateMode // "auto"' "$HOME/.claude/settings.json" 2>/dev/null || echo "auto")
  if [ "$TEAMMATE_MODE" = "tmux" ] && ! command -v tmux &>/dev/null; then
    hook_log "WARNING: teammateMode=tmux but tmux not installed"
    echo '{"systemMessage":"tmux is not installed. Agent teams will run in-process mode (navigate between teammates with Shift+Down). For split-pane view, install tmux: brew install tmux (macOS) or apt install tmux (Linux)."}' || true
  fi

  # Team size guidance
  if [ -f "$TEAM_CONFIG" ]; then
    MEMBER_COUNT=$(jq '.members | length' "$TEAM_CONFIG" 2>/dev/null || echo "0")
    if [ "${MEMBER_COUNT:-0}" -ge 5 ]; then
      hook_log "team size warning: $MEMBER_COUNT members"
      echo '{"systemMessage":"Team has '"$MEMBER_COUNT"' teammates. Optimal team size is 3-5 - coordination overhead increases beyond that. Consider whether all teammates are necessary."}' || true
    fi
  fi

  # All checks pass — allow teammate spawn
  exit 0
fi

# BLOCK: ALL Agent calls without team — no exceptions
BLOCKED="Implementation agents need a team for coordination. Call TeamCreate first, then spawn named teammates with team_name, name, and isolation: worktree parameters. Only Explore and Plan agents work without a team (they are read-only)."

HOOK_DECISION="block" HOOK_REASON="$BLOCKED"

jq -n \
  --arg reason "$BLOCKED" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "block",
      permissionDecisionReason: $reason
    }
  }'

exit 0
