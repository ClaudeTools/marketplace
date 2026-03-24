#!/usr/bin/env bash
# enforce-worktree-isolation.sh — Block destructive tools on main worktree
# PreToolUse:Edit|Write|Bash|NotebookEdit — forces EnterWorktree before mutations
# Read/Grep/Glob are allowed so Claude can research before entering a worktree.
# Uses exit 2 (not permissionDecision JSON) because deny is broken: github.com/anthropics/claude-code/issues/4669

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

# In a worktree? Allow.
if is_worktree; then
  exit 0
fi

# Allow worktree creation commands through — these are how you GET into a worktree.
# The tool_name is the Claude Code tool (Bash, Edit, etc.) and tool_input contains the command.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
if [[ "$TOOL_NAME" == "Bash" ]]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  # Allow git worktree operations and EnterWorktree setup commands
  if echo "$BASH_CMD" | grep -qE '^\s*(git\s+worktree|mkdir\s+-p\s+.*\.claude/worktrees)'; then
    hook_log "enforce-worktree-isolation: allowing worktree setup command"
    exit 0
  fi
fi

# Not in a worktree — block via exit 2 (stderr becomes the reason shown to Claude).
hook_log "enforce-worktree-isolation: blocked on main worktree"
echo "Call EnterWorktree first. File modifications and commands are blocked on the main worktree." >&2
exit 2
