#!/bin/bash
# TeammateIdle + TaskCompleted hook — ensures work is committed to git
# Blocks if there are uncommitted changes in the working directory
# Exit 2 = reject (must commit before completing/going idle)
# Exit 0 = allow

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# Only check in git repos
if ! git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
  exit 0
fi

# Check for uncommitted changes to tracked files
UNCOMMITTED=$(git -C "$CWD" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

# If staged but not committed — they forgot to commit
if [ "$STAGED" -gt 0 ]; then
  HOOK_DECISION="reject" HOOK_REASON="staged but uncommitted changes"
  cat >&2 <<EOF
You have ${STAGED} staged files that are not committed.
Uncommitted work is lost during context compaction and is invisible to teammates.

Run: git commit -m "feat: <description>"
EOF
  record_hook_outcome "enforce-git-commits" "TaskCompleted" "block" "" "" "" "$MODEL_FAMILY"
  exit 2
fi

# If modified tracked files — they forgot to stage and commit
UNCOMMITTED_LIMIT=$(get_threshold "uncommitted_file_limit" "$MODEL_FAMILY")
UNCOMMITTED_LIMIT=${UNCOMMITTED_LIMIT%.*}
if [ "$UNCOMMITTED" -gt "$UNCOMMITTED_LIMIT" ]; then
  HOOK_DECISION="reject" HOOK_REASON="${UNCOMMITTED} uncommitted modified files"
  cat >&2 <<EOF
You have ${UNCOMMITTED} modified files that are not committed.
Uncommitted work is lost during context compaction and is invisible to teammates.

Stage and commit:
  git add <specific files you changed>
  git commit -m "feat: <description>"
EOF
  record_hook_outcome "enforce-git-commits" "TaskCompleted" "block" "" "uncommitted_file_limit" "$UNCOMMITTED_LIMIT" "$MODEL_FAMILY"
  exit 2
fi

record_hook_outcome "enforce-git-commits" "TaskCompleted" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
