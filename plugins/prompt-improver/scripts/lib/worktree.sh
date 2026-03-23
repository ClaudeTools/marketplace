#!/usr/bin/env bash
# worktree.sh — Shared library for worktree-aware paths and session identity
# Usage: source "$(dirname "$0")/lib/worktree.sh"
#
# Provides:
#   get_repo_root()          — main repository root (even from inside a worktree)
#   get_worktree_root()      — current worktree root (or repo root if not in one)
#   is_worktree()            — 0 if inside a git worktree, 1 otherwise
#   get_session_id([input])  — session ID from hook input > $SESSION_ID > $PPID
#   session_tmp_path(name)   — /tmp/claude-{name}-{session_id}

[[ -n "${_WORKTREE_SH_LOADED:-}" ]] && return 0
_WORKTREE_SH_LOADED=1

# Returns the main repository root (even from inside a worktree).
# Uses git-common-dir to find the shared .git, then derives the repo root.
get_repo_root() {
  local git_common
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    # Fallback: not in a git repo or old git version
    git rev-parse --show-toplevel 2>/dev/null || pwd
    return 0
  }

  # git-common-dir returns the path to the shared .git directory:
  #   Normal repo:  /path/to/repo/.git          -> strip /.git
  #   Worktree:     /path/to/repo/.git           (same — common dir is always main .git)
  if [[ "$git_common" == */.git/worktrees/* ]]; then
    # Should not happen with --git-common-dir, but be defensive
    echo "${git_common%%/.git/*}"
  elif [[ "$git_common" == */.git ]]; then
    echo "${git_common%/.git}"
  else
    # Bare repo or unexpected layout — fall back
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

# Returns the current worktree's root (or repo root if not in a worktree).
get_worktree_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Returns 0 if running inside a git worktree, 1 otherwise.
is_worktree() {
  local git_common git_dir
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git_dir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  # In a worktree, git-dir differs from git-common-dir
  [[ "$git_dir" != "$git_common" ]]
}

# Returns session ID with fallback chain:
#   1. Hook input .session_id (from $1 JSON)
#   2. $SESSION_ID environment variable
#   3. $PPID
get_session_id() {
  local input="${1:-}"
  local sid=""

  # Try hook input JSON first
  if [[ -n "$input" ]] && command -v jq &>/dev/null; then
    sid=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null) || true
  fi

  # Fallback to env var
  if [[ -z "$sid" ]]; then
    sid="${SESSION_ID:-}"
  fi

  # Final fallback to PPID
  if [[ -z "$sid" ]]; then
    sid="$PPID"
  fi

  echo "$sid"
}

# Returns a session-scoped temp file path.
# Usage: session_tmp_path "edit-counts"
#   -> /tmp/claude-edit-counts-{session_id}
session_tmp_path() {
  local name="$1"
  local sid
  sid=$(get_session_id "${INPUT:-}")
  echo "/tmp/claude-${name}-${sid}"
}
