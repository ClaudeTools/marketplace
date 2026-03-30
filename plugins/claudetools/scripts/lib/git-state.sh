#!/usr/bin/env bash
# git-state.sh — Shared git state helpers with caching via exports
#
# Functions cache their results in exported environment variables so that
# multiple validators in the same dispatcher can share a single git fork.
# All functions take an optional DIR argument (defaults to CWD or ".").

# git_is_repo [DIR] — Returns 0 if inside a git repo, 1 otherwise.
git_is_repo() {
  local dir="${1:-.}"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# git_project_root [DIR] — Echoes the git toplevel path. Empty if not a repo.
# Caches result in _CACHED_PROJECT_ROOT.
git_project_root() {
  local dir="${1:-.}"
  if [ -n "${_CACHED_PROJECT_ROOT:-}" ]; then
    echo "$_CACHED_PROJECT_ROOT"
    return 0
  fi
  local root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  export _CACHED_PROJECT_ROOT="$root"
  echo "$root"
}

# git_changed_files [DIR] — Echoes newline-separated list of changed files
# (staged + unstaged + untracked, deduped, filtered of system artifacts).
# Caches result in _CACHED_CHANGED_FILES.
git_changed_files() {
  local dir="${1:-.}"
  if [ -n "${_CACHED_CHANGED_FILES+set}" ]; then
    echo "$_CACHED_CHANGED_FILES"
    return 0
  fi
  local staged unstaged untracked all filtered
  staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null || true)
  unstaged=$(git -C "$dir" diff --name-only 2>/dev/null || true)
  untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null || true)
  all=$(printf '%s\n%s\n%s' "$staged" "$unstaged" "$untracked" | sort -u | sed '/^$/d')
  filtered=$(echo "$all" | grep -vE '^\.(claude|DS_Store)|\.lock$|\.tsbuildinfo$|^node_modules/|^\.git/' | sed '/^$/d' || true)
  export _CACHED_CHANGED_FILES="$filtered"
  echo "$filtered"
}

# git_status_porcelain [DIR] — Single git status --porcelain call.
# Caches result in _CACHED_GIT_STATUS.
git_status_porcelain() {
  local dir="${1:-.}"
  if [ -n "${_CACHED_GIT_STATUS+set}" ]; then
    echo "$_CACHED_GIT_STATUS"
    return 0
  fi
  local status
  status=$(git -C "$dir" status --porcelain 2>/dev/null || true)
  export _CACHED_GIT_STATUS="$status"
  echo "$status"
}
