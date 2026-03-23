#!/usr/bin/env bash
# enforce-worktree-isolation.sh — Block destructive tools on main worktree
# PreToolUse:Edit|Write|Bash|NotebookEdit — forces EnterWorktree before mutations
# Read/Grep/Glob are allowed so Claude can research before entering a worktree.
# Exit 0 always — denial done via JSON stdout

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

# In a worktree? Allow.
if is_worktree; then
  exit 0
fi

# Not in a worktree — deny destructive tools.
jq -n --arg reason "Call EnterWorktree first. File modifications and commands are blocked on the main worktree." \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'

hook_log "enforce-worktree-isolation: denied on main worktree"
exit 0
