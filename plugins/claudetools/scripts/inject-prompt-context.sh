#!/bin/bash
# inject-prompt-context.sh — UserPromptSubmit hook
# Injects lightweight context (git state, active tasks, recent failures)
# into every prompt. Stdout becomes visible context to Claude.
# Must always exit 0 and complete under 5 seconds.

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/detect-project.sh"

INPUT=$(cat)

hook_log "inject-prompt-context started"

# --- Git section ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  commits=$(git log --oneline -3 --no-decorate 2>/dev/null)

  if [ -n "$branch" ]; then
    echo "[git] branch: ${branch} | uncommitted: ${uncommitted}"
    if [ -n "$commits" ]; then
      echo "[git] recent commits:"
      echo "$commits" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi
fi

# --- Active task section ---
task_dir="$HOME/.claude/tasks"
if [ -d "$task_dir" ]; then
  for f in "$task_dir"/*.json; do
    [ -f "$f" ] || continue
    status=$(jq -r '.status // ""' "$f" 2>/dev/null)
    if [ "$status" = "in_progress" ]; then
      title=$(jq -r '.title // "untitled"' "$f" 2>/dev/null)
      echo "[task] active: ${title}"
    fi
  done
fi

# --- Recent failures section ---
failure_log="/tmp/claude-failures-${PPID}.jsonl"
if [ -f "$failure_log" ]; then
  cutoff=$(date -v-5M +%s 2>/dev/null || date -d '5 minutes ago' +%s 2>/dev/null)
  if [ -n "$cutoff" ]; then
    count=0
    while IFS= read -r line; do
      ts=$(echo "$line" | jq -r '.timestamp // 0' 2>/dev/null)
      if [ -n "$ts" ] && [ "$ts" -ge "$cutoff" ] 2>/dev/null; then
        count=$((count + 1))
      fi
    done < "$failure_log"
    if [ "$count" -gt 0 ]; then
      echo "[warn] Recent failures: ${count} (check approach)"
    fi
  fi
fi

hook_log "inject-prompt-context complete"
exit 0
