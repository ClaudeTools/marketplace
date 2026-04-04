#!/usr/bin/env bash
# restore-after-compact.sh — PostCompact hook: restore context after compaction
# Reads state saved by archive-before-compact.sh and outputs context to stdout.
# Uses a 4096-byte budget with 3 priority tiers to prevent token waste.
# Always exits 0.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
# shellcheck source=lib/resolve-srcpilot.sh
source "$(dirname "$0")/lib/resolve-srcpilot.sh"

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

# --- Byte budget system ---
TOTAL_BUDGET=4096
P1_BUDGET=2048   # git state + tasks + session reads (highest priority)
P2_BUDGET=1024   # abbreviated project map
P3_BUDGET=1024   # file overviews (lowest priority)
BYTES_USED=0

# Emit a block if it fits within the tier budget and total budget
# Usage: emit_if_fits "$content" $tier_budget
# Prints the content (possibly truncated) and updates BYTES_USED
emit_if_fits() {
  local content="$1"
  local tier_budget="$2"
  local remaining=$((TOTAL_BUDGET - BYTES_USED))
  local allowed=$((tier_budget < remaining ? tier_budget : remaining))

  if [ "$allowed" -le 0 ]; then
    return 1
  fi

  local content_len=${#content}
  if [ "$content_len" -le "$allowed" ]; then
    printf '%s' "$content"
    BYTES_USED=$((BYTES_USED + content_len))
  else
    # Truncate at budget boundary, append marker
    local marker=$'\n... (truncated)\n'
    local cut=$((allowed - ${#marker}))
    if [ "$cut" -gt 0 ]; then
      printf '%s' "${content:0:$cut}${marker}"
      BYTES_USED=$((BYTES_USED + cut + ${#marker}))
    fi
  fi
}

# --- P1: Git state + tasks + session reads (highest priority) ---
P1_CONTENT=""

# Read state
branch=$(jq -r '.git_branch // ""' "$STATE_FILE" 2>/dev/null) || branch=""
uncommitted=$(jq -r '.uncommitted_count // 0' "$STATE_FILE" 2>/dev/null) || uncommitted="0"
recent_commits=$(jq -r '.recent_commits // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || recent_commits=""
active_tasks=$(jq -r '.active_tasks // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || active_tasks=""
modified_files=$(jq -r '.modified_files // [] | join(", ")' "$STATE_FILE" 2>/dev/null) || modified_files=""
project_type=$(jq -r '.project_type // "unknown"' "$STATE_FILE" 2>/dev/null) || project_type="unknown"

P1_CONTENT="=== Context Recovery (post-compaction) ==="$'\n'
[ -n "$branch" ] && P1_CONTENT+="Branch: ${branch} | Uncommitted: ${uncommitted} files"$'\n'
[ -n "$recent_commits" ] && P1_CONTENT+="Recent commits: ${recent_commits}"$'\n'
[ -n "$active_tasks" ] && P1_CONTENT+="Active task: ${active_tasks}"$'\n'
[ -n "$modified_files" ] && P1_CONTENT+="Modified files: ${modified_files}"$'\n'
P1_CONTENT+="Project type: ${project_type}"$'\n'

# Session reads — remind agent what it already read
session_reads=$(jq -r '.session_reads // [] | .[-10:][]' "$STATE_FILE" 2>/dev/null) || session_reads=""
if [ -n "$session_reads" ]; then
  P1_CONTENT+=$'\n'"=== Files Already in Context (do NOT re-read) ==="$'\n'
  while IFS= read -r rpath; do
    [ -n "$rpath" ] && P1_CONTENT+="  $rpath"$'\n'
  done <<< "$session_reads"
fi

emit_if_fits "$P1_CONTENT" "$P1_BUDGET"

# Cross-platform timeout wrapper
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

# --- P2: Abbreviated project map ---
if command -v "$SRCPILOT" &>/dev/null && [ "$BYTES_USED" -lt "$TOTAL_BUDGET" ]; then
  MAP_OUTPUT=$(run_with_timeout 3 "$SRCPILOT" map 2>/dev/null | head -20) || true
  if [ -n "$MAP_OUTPUT" ]; then
    P2_CONTENT=$'\n'"=== Codebase Map (abbreviated) ==="$'\n'"$MAP_OUTPUT"$'\n'
    emit_if_fits "$P2_CONTENT" "$P2_BUDGET"
  fi
fi

# --- P3: File overviews for modified files (lowest priority) ---
if command -v "$SRCPILOT" &>/dev/null && [ "$BYTES_USED" -lt "$TOTAL_BUDGET" ]; then
  mod_files_json=$(jq -r '.modified_files // []' "$STATE_FILE" 2>/dev/null) || mod_files_json="[]"
  if [ -n "$mod_files_json" ] && [ "$mod_files_json" != "[]" ]; then
    mod_list=$(echo "$mod_files_json" | jq -r '.[:3][]' 2>/dev/null) || mod_list=""
    if [ -n "$mod_list" ]; then
      P3_CONTENT=$'\n'"=== Modified File Symbols ==="$'\n'
      while IFS= read -r mpath; do
        [ -z "$mpath" ] && continue
        overview=$(run_with_timeout 2 "$SRCPILOT" file-overview "$mpath" 2>/dev/null | head -10) || true
        if [ -n "$overview" ]; then
          P3_CONTENT+="$overview"$'\n'
        fi
      done <<< "$mod_list"
      emit_if_fits "$P3_CONTENT" "$P3_BUDGET"
    fi
  fi
fi

# Cleanup temp file
rm -f "$STATE_FILE"

hook_log "context restored (${BYTES_USED}/${TOTAL_BUDGET} bytes used)"
exit 0
