#!/usr/bin/env bash
# track-worktree-session.sh — SessionStart/WorktreeCreate hook
# Records worktree session metadata to a persistent log so sessions
# can be recovered or at least identified after crashes.
#
# Problem: Claude Code stores session transcripts in ~/.claude/projects/
# keyed by CWD path. If a worktree session crashes, the transcript is
# never persisted and the session is lost forever.
#
# Solution: Record session metadata (ID, worktree path, branch, timestamp)
# to a JSONL file in the repo's .claude/ directory on every session start.
# This at minimum tells you WHAT was running WHERE and WHEN, even if the
# full transcript is gone.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

SID=$(get_session_id "$INPUT")
[[ -z "$SID" ]] && exit 0

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
WT_ROOT=$(get_worktree_root)
REPO_ROOT=$(get_repo_root)
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
IS_WT=false
is_worktree && IS_WT=true

# Session log lives at repo root .claude/worktree-sessions.jsonl
# This persists across worktrees since they share the repo's .claude/
LOG_DIR="${REPO_ROOT}/.claude"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="${LOG_DIR}/worktree-sessions.jsonl"

# Claude Code session transcript path (where Claude stores its logs)
CC_PROJECT_KEY=$(echo "$WT_ROOT" | sed 's|^/|-|; s|/|-|g')
CC_SESSION_DIR="${HOME}/.claude/projects/${CC_PROJECT_KEY}"

# Record session start
ENTRY=$(jq -cn \
  --arg sid "$SID" \
  --arg event "$HOOK_EVENT" \
  --arg worktree "$WT_ROOT" \
  --arg branch "$BRANCH" \
  --arg repo "$REPO_ROOT" \
  --argjson is_worktree "$IS_WT" \
  --arg cc_logs "$CC_SESSION_DIR" \
  --arg pid "$$" \
  --arg ts "$(date -Iseconds)" \
  '{
    session_id: $sid,
    event: $event,
    worktree: $worktree,
    branch: $branch,
    repo: $repo,
    is_worktree: $is_worktree,
    cc_session_dir: $cc_logs,
    pid: ($pid | tonumber),
    timestamp: $ts
  }' 2>/dev/null) || exit 0

echo "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

# Also snapshot the current git state for crash recovery context
if [[ "$IS_WT" == "true" ]]; then
  SNAPSHOT_DIR="${LOG_DIR}/worktree-snapshots"
  mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || true
  SNAPSHOT_FILE="${SNAPSHOT_DIR}/${SID:0:8}.json"

  # Capture: uncommitted files, recent commits, active tasks
  UNCOMMITTED=$(cd "$WT_ROOT" && git status --porcelain 2>/dev/null | wc -l)
  RECENT_COMMITS=$(cd "$WT_ROOT" && git log --oneline -5 2>/dev/null || echo "none")
  TASKS_FILE="${WT_ROOT}/.tasks/tasks.json"
  ACTIVE_TASKS="none"
  if [[ -f "$TASKS_FILE" ]]; then
    ACTIVE_TASKS=$(jq -r '[.[] | select(.status == "in_progress")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
  fi

  jq -cn \
    --arg sid "$SID" \
    --arg worktree "$WT_ROOT" \
    --arg branch "$BRANCH" \
    --arg uncommitted "$UNCOMMITTED" \
    --arg recent_commits "$RECENT_COMMITS" \
    --arg active_tasks "$ACTIVE_TASKS" \
    --arg ts "$(date -Iseconds)" \
    '{
      session_id: $sid,
      worktree: $worktree,
      branch: $branch,
      uncommitted_files: ($uncommitted | tonumber),
      recent_commits: $recent_commits,
      active_tasks: $active_tasks,
      started: $ts,
      status: "active"
    }' > "$SNAPSHOT_FILE" 2>/dev/null || true

  hook_log "track-worktree-session: recorded snapshot for $SID in $WT_ROOT (branch=$BRANCH, uncommitted=$UNCOMMITTED)"
fi

exit 0
