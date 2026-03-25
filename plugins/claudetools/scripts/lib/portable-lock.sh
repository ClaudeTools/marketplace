#!/usr/bin/env bash
# portable-lock.sh — Cross-platform file locking (Linux + macOS)
#
# Linux: uses flock (file-descriptor based, fast)
# macOS/POSIX: uses mkdir (atomic on all POSIX systems)
#
# Usage:
#   source "$(dirname "$0")/lib/portable-lock.sh"
#   portable_trylock "/path/to/lockfile" || return 0
#   # ... do locked work ...
#   portable_unlock "/path/to/lockfile"

[[ -n "${_PORTABLE_LOCK_LOADED:-}" ]] && return 0
_PORTABLE_LOCK_LOADED=1

# Acquire a blocking lock (waits up to 2 seconds).
# Returns 0 on success, 1 on timeout.
portable_lock() {
  local lockfile="$1"
  if command -v flock &>/dev/null; then
    exec 200>"$lockfile"
    flock -w 2 200 2>/dev/null
    return $?
  else
    local lockdir="${lockfile}.d"
    local retries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      if [[ -d "$lockdir" ]]; then
        local mtime now age
        now=$(date +%s)
        mtime=$(stat -f%m "$lockdir" 2>/dev/null || stat -c%Y "$lockdir" 2>/dev/null || echo "$now")
        age=$((now - mtime))
        if [[ "$age" -gt 60 ]]; then
          rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir" 2>/dev/null
          continue
        fi
      fi
      retries=$((retries + 1))
      [[ "$retries" -gt 20 ]] && return 1
      sleep 0.1 2>/dev/null || sleep 1
    done
    return 0
  fi
}

# Try to acquire a non-blocking lock.
# Returns 0 if acquired, 1 if already held (caller should skip).
portable_trylock() {
  local lockfile="$1"
  if command -v flock &>/dev/null; then
    exec 200>"$lockfile"
    flock -n 200 2>/dev/null
    return $?
  else
    local lockdir="${lockfile}.d"
    if [[ -d "$lockdir" ]]; then
      local mtime now age
      now=$(date +%s)
      mtime=$(stat -f%m "$lockdir" 2>/dev/null || stat -c%Y "$lockdir" 2>/dev/null || echo "$now")
      age=$((now - mtime))
      [[ "$age" -gt 60 ]] && { rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir" 2>/dev/null; }
    fi
    mkdir "$lockdir" 2>/dev/null
    return $?
  fi
}

# Release a lock.
portable_unlock() {
  local lockfile="$1"
  if command -v flock &>/dev/null; then
    flock -u 200 2>/dev/null
    exec 200>&- 2>/dev/null
  else
    rmdir "${lockfile}.d" 2>/dev/null
  fi
}
