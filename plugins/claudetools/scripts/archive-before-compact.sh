#!/usr/bin/env bash
# archive-before-compact.sh — PreCompact hook: save critical state before context compaction
# State is written to /tmp/claude-precompact-{session_id}.json for PostCompact to restore.
# Always exits 0 — must never block compaction.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/detect-project.sh"
source "$(dirname "$0")/lib/worktree.sh"

# Read hook input from stdin
INPUT=$(cat)

session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

if [ -z "$session_id" ]; then
  hook_log "no session_id, skipping"
  exit 0
fi

STATE_FILE="/tmp/claude-precompact-${session_id}.json"

hook_log "archiving state to ${STATE_FILE}"

CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# Git info (safe defaults if not in a git repo)
git_branch=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
uncommitted_count=$(git -C "$CWD" status --short 2>/dev/null | wc -l | tr -d ' ')
modified_files=$(git -C "$CWD" diff --name-only 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

# Recent commits — last 3 subjects as JSON array
recent_commits=$(git -C "$CWD" log --oneline -3 --format='%s' 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

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

# Session reads from srcpilot — merge ALL session reads files
session_reads='[]'
SESSION_IDS_FILE="$(get_worktree_root)/.srcpilot/session-ids"
if [ -f "$SESSION_IDS_FILE" ]; then
  ALL_READS=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    READS_FILE="/tmp/srcpilot-reads-${sid}.jsonl"
    if [ -f "$READS_FILE" ]; then
      ALL_READS="${ALL_READS}$(cat "$READS_FILE" 2>/dev/null || true)"$'\n'
    fi
  done < "$SESSION_IDS_FILE"
  if [ -n "$ALL_READS" ]; then
    session_reads=$(echo "$ALL_READS" | jq -R -s 'split("\n") | map(select(length > 0)) | map(fromjson? | .path // empty) | map(select(length > 0)) | unique' 2>/dev/null || echo '[]')
  fi
fi

# Build JSON state file
jq -n \
  --arg branch "$git_branch" \
  --arg uncommitted "$uncommitted_count" \
  --argjson recent_commits "$recent_commits" \
  --argjson active_tasks "$active_tasks" \
  --argjson modified_files "$modified_files" \
  --argjson session_reads "$session_reads" \
  --arg project_type "$project_type" \
  --arg timestamp "$timestamp" \
  '{
    git_branch: $branch,
    uncommitted_count: ($uncommitted | tonumber),
    recent_commits: $recent_commits,
    active_tasks: $active_tasks,
    modified_files: $modified_files,
    session_reads: $session_reads,
    project_type: $project_type,
    timestamp: $timestamp
  }' > "$STATE_FILE" 2>/dev/null || {
  hook_log "failed to write state file"
  exit 0
}

# Append compaction marker to all session reads files
# This lets loadSessionContext() know reads before this point are compacted
if [ -f "$SESSION_IDS_FILE" ]; then
  COMPACT_TS=$(date +%s)
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    READS_FILE="/tmp/srcpilot-reads-${sid}.jsonl"
    [ -f "$READS_FILE" ] || continue
    jq -nc --argjson t "$COMPACT_TS" '{"event":"compact","ts":$t}' >> "$READS_FILE" 2>/dev/null || true
  done < "$SESSION_IDS_FILE"
fi

hook_log "state archived successfully"
exit 0
