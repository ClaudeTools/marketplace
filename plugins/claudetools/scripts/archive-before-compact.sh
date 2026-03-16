#!/usr/bin/env bash
# archive-before-compact.sh — PreCompact hook: save critical state before context compaction
# State is written to /tmp/claude-precompact-{session_id}.json for PostCompact to restore.
# Always exits 0 — must never block compaction.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/detect-project.sh"

# Read hook input from stdin
INPUT=$(cat)

session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

if [ -z "$session_id" ]; then
  hook_log "no session_id, skipping"
  exit 0
fi

STATE_FILE="/tmp/claude-precompact-${session_id}.json"

hook_log "archiving state to ${STATE_FILE}"

# Git info (safe defaults if not in a git repo)
git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
uncommitted_count=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
modified_files=$(git diff --name-only 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

# Recent commits — last 3 subjects as JSON array
recent_commits=$(git log --oneline -3 --format='%s' 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

# Active tasks from ~/.claude/tasks/
active_tasks='[]'
if [ -d "$HOME/.claude/tasks" ]; then
  active_tasks=$(
    find "$HOME/.claude/tasks" -name '*.json' -type f 2>/dev/null \
      | while read -r f; do
          jq -r 'select(.status == "in_progress") | .title // empty' "$f" 2>/dev/null
        done \
      | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]'
  )
fi

# Project type
detect_project_type
project_type="${PROJECT_TYPE:-general}"

# Timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON state file
jq -n \
  --arg branch "$git_branch" \
  --arg uncommitted "$uncommitted_count" \
  --argjson recent_commits "$recent_commits" \
  --argjson active_tasks "$active_tasks" \
  --argjson modified_files "$modified_files" \
  --arg project_type "$project_type" \
  --arg timestamp "$timestamp" \
  '{
    git_branch: $branch,
    uncommitted_count: ($uncommitted | tonumber),
    recent_commits: $recent_commits,
    active_tasks: $active_tasks,
    modified_files: $modified_files,
    project_type: $project_type,
    timestamp: $timestamp
  }' > "$STATE_FILE" 2>/dev/null || {
  hook_log "failed to write state file"
  exit 0
}

hook_log "state archived successfully"
exit 0
