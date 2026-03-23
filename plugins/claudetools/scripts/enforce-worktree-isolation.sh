#!/usr/bin/env bash
# enforce-worktree-isolation.sh — Block ALL tools on main worktree
# PreToolUse hook — forces EnterWorktree before any work
# Exit 0 always — blocking done via JSON stdout

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

# In a worktree? Allow.
if is_worktree; then
  exit 0
fi

# Not in a worktree — block.
jq -n --arg reason "Call EnterWorktree first. All tools are blocked on the main worktree." \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'

hook_log "enforce-worktree-isolation: blocked on main worktree"
exit 0
