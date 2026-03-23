#!/usr/bin/env bash
# enforce-worktree-isolation.sh — Block edits on main worktree
# PreToolUse:Edit|Write hook
# Exit 0 always — blocking done via JSON stdout

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

hook_log "enforce-worktree-isolation: checking"
trap 'hook_log "enforce-worktree-isolation: result=$? decision=${HOOK_DECISION:-allow}"' EXIT

HOOK_DECISION="allow"

# If already in a worktree, allow immediately
if is_worktree; then
  exit 0
fi

# Not in a worktree — BLOCK
HOOK_DECISION="block"
BLOCKED="You are editing files on the MAIN worktree. This causes conflicts with other sessions. Call EnterWorktree first to create an isolated workspace, then retry your edit."

jq -n --arg reason "$BLOCKED" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'

exit 0
