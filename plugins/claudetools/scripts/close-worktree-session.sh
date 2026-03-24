#!/usr/bin/env bash
# close-worktree-session.sh — Stop/SessionEnd hook
# Marks the worktree session snapshot as "closed" so we can identify
# sessions that crashed (still marked "active" with no close record).

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"

SID=$(get_session_id "$INPUT")
[[ -z "$SID" ]] && exit 0

REPO_ROOT=$(get_repo_root)
SNAPSHOT_FILE="${REPO_ROOT}/.claude/worktree-snapshots/${SID:0:8}.json"

# Update snapshot status to closed
if [[ -f "$SNAPSHOT_FILE" ]]; then
  WT_ROOT=$(get_worktree_root)
  UNCOMMITTED=$(cd "$WT_ROOT" && git status --porcelain 2>/dev/null | wc -l)
  RECENT_COMMITS=$(cd "$WT_ROOT" && git log --oneline -5 2>/dev/null || echo "none")

  # Read existing and update
  UPDATED=$(jq \
    --arg status "closed" \
    --arg closed_at "$(date -Iseconds)" \
    --arg uncommitted "$UNCOMMITTED" \
    --arg recent_commits "$RECENT_COMMITS" \
    '. + {status: $status, closed_at: $closed_at, uncommitted_at_close: ($uncommitted | tonumber), recent_commits_at_close: $recent_commits}' \
    "$SNAPSHOT_FILE" 2>/dev/null) || exit 0

  echo "$UPDATED" > "$SNAPSHOT_FILE" 2>/dev/null || true
  hook_log "close-worktree-session: marked $SID as closed (uncommitted=$UNCOMMITTED)"
fi

# Also append close record to the session log
LOG_FILE="${REPO_ROOT}/.claude/worktree-sessions.jsonl"
if [[ -f "$LOG_FILE" ]]; then
  jq -cn \
    --arg sid "$SID" \
    --arg event "close" \
    --arg worktree "$(get_worktree_root)" \
    --arg ts "$(date -Iseconds)" \
    '{session_id: $sid, event: $event, worktree: $worktree, timestamp: $ts}' \
    >> "$LOG_FILE" 2>/dev/null || true
fi

exit 0
