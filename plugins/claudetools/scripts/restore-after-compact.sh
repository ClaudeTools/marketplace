#!/usr/bin/env bash
# restore-after-compact.sh — PostCompact hook: restore context after compaction
# Reads state saved by archive-before-compact.sh and outputs context to stdout.
# Always exits 0.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"

# Read hook input from stdin
INPUT=$(cat)

session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

if [ -z "$session_id" ]; then
  hook_log "no session_id, skipping"
  exit 0
fi

STATE_FILE="/tmp/claude-precompact-${session_id}.json"

# If no state file, exit silently (first compaction or PreCompact didn't run)
if [ ! -f "$STATE_FILE" ]; then
  hook_log "no state file found, skipping"
  exit 0
fi

hook_log "restoring context from ${STATE_FILE}"

# Read state
branch=$(jq -r '.git_branch // ""' "$STATE_FILE" 2>/dev/null) || branch=""
uncommitted=$(jq -r '.uncommitted_count // 0' "$STATE_FILE" 2>/dev/null) || uncommitted="0"
recent_commits=$(jq -r '.recent_commits // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || recent_commits=""
active_tasks=$(jq -r '.active_tasks // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || active_tasks=""
modified_files=$(jq -r '.modified_files // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || modified_files=""
project_type=$(jq -r '.project_type // "unknown"' "$STATE_FILE" 2>/dev/null) || project_type="unknown"

# Output context recovery block to stdout
echo "=== Context Recovery (post-compaction) ==="
if [ -n "$branch" ]; then
  echo "Branch: ${branch} | Uncommitted: ${uncommitted} files"
fi
if [ -n "$recent_commits" ]; then
  echo "Recent commits: ${recent_commits}"
fi
if [ -n "$active_tasks" ]; then
  echo "Active task: ${active_tasks}"
fi
if [ -n "$modified_files" ]; then
  echo "Modified files: ${modified_files}"
fi
echo "Project type: ${project_type}"

# Cleanup temp file
rm -f "$STATE_FILE"

hook_log "context restored and state file cleaned up"
exit 0
