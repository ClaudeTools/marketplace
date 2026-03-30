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

# git_state_cache_path — Returns session-scoped git state cache file path.
git_state_cache_path() {
  local session_id="${SESSION_ID:-${_deploy_session_id:-$$}}"
  echo "/tmp/claude-git-state-${session_id}.json"
}

# git_save_state [DIR] — Write git state to session temp file for cross-hook sharing.
git_save_state() {
  local dir="${1:-.}"
  local cache
  cache=$(git_state_cache_path)
  local branch is_repo
  is_repo=false
  git_is_repo "$dir" && is_repo=true
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  local changed_files
  changed_files=$(git_changed_files "$dir" | tr '\n' '|')
  printf '{"is_repo":%s,"branch":"%s","changed_files":"%s","ts":%s}\n' \
    "$is_repo" "$branch" "$changed_files" "$(date +%s)" > "$cache" 2>/dev/null || true
}

# git_load_state — Load cached git state if fresh (< 30s). Returns 0 if loaded, 1 if stale.
git_load_state() {
  local cache
  cache=$(git_state_cache_path)
  [ -f "$cache" ] || return 1
  local cache_age
  cache_age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0) ))
  [ "$cache_age" -gt 30 ] && return 1
  export _CACHED_GIT_IS_REPO=$(jq -r '.is_repo' "$cache" 2>/dev/null || echo "false")
  export _CACHED_GIT_BRANCH=$(jq -r '.branch' "$cache" 2>/dev/null || echo "")
  export _CACHED_CHANGED_FILES=$(jq -r '.changed_files' "$cache" 2>/dev/null | tr '|' '\n' || true)
  return 0
}
