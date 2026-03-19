#!/bin/bash
# Stop hook (async) — Sonnet-powered memory extraction
# Runs in parallel with session stop. Never blocks.
# Reads session transcript, asks Sonnet to identify learnings,
# writes memory files directly to the project memory directory.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/telemetry.sh" 2>/dev/null || true

INPUT=$(cat 2>/dev/null || true)
hook_log "invoked"

# Need claude CLI
if ! command -v claude &>/dev/null; then
  hook_log "memory-reflect: claude CLI not found, skipping"
  exit 0
fi

# Get session info
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
[ -z "$CWD" ] && CWD="."

# Check session age — skip short sessions
START_MARKER="/tmp/.claude-session-start-${SESSION_ID}"
if [ -f "$START_MARKER" ]; then
  START_TIME=$(stat -c '%Y' "$START_MARKER" 2>/dev/null || stat -f '%m' "$START_MARKER" 2>/dev/null || echo 0)
  NOW_TIME=$(date +%s)
  SESSION_AGE_MIN=$(( (NOW_TIME - START_TIME) / 60 ))
  if [ "$SESSION_AGE_MIN" -lt 5 ]; then
    hook_log "memory-reflect: session too short (${SESSION_AGE_MIN} min), skipping"
    exit 0
  fi
fi

# Memory directory
MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
mkdir -p "$MEMORY_DIR" 2>/dev/null || exit 0

# Check if memories were already saved this session
if [ -f "$START_MARKER" ]; then
  NEW_MEMORIES=$(find "$MEMORY_DIR" -name "*.md" -newer "$START_MARKER" -not -name "MEMORY.md" -not -name "auto_session_summary.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NEW_MEMORIES" -gt 0 ]; then
    hook_log "memory-reflect: ${NEW_MEMORIES} memories already saved, skipping"
    emit_event "memory-reflect" "already_saved" "allow" "0" "{\"count\":${NEW_MEMORIES}}" 2>/dev/null || true
    exit 0
  fi
fi

# Get transcript
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  hook_log "memory-reflect: no transcript found"
  exit 0
fi

# Extract full session context — all user messages + assistant key decisions
# The transcript is JSONL with role fields. Pull user messages (the richest signal)
# and assistant messages that contain decisions/corrections.
SESSION_CONTEXT=$(jq -r '
  if .role == "human" or .role == "user" then
    "USER: " + (
      if (.content | type) == "array" then
        [.content[] | select(type == "string" or .type == "text") |
         if type == "string" then . else .text end] | join(" ")
      else (.content // "") end
    ) | .[0:500]
  elif .role == "assistant" then
    "ASSISTANT: " + (
      if (.content | type) == "array" then
        [.content[] | select(.type == "text") | .text] | join(" ")
      else (.content // "") end
    ) | .[0:300]
  else empty end
' "$TRANSCRIPT" 2>/dev/null | head -c 30000 || true)
[ -z "$SESSION_CONTEXT" ] && exit 0

# Existing memories (so we don't duplicate)
EXISTING=""
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  EXISTING=$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true)
fi

hook_log "memory-reflect: invoking Sonnet for memory extraction"

# Call Sonnet via claude CLI with a focused extraction prompt
RESULT=$(echo "$SESSION_CONTEXT" | timeout 45 claude -p "You are a memory extraction agent. Review this session transcript and identify NEW learnings worth saving for future sessions.

EXISTING MEMORIES (do not duplicate these):
${EXISTING}

For each new learning, output EXACTLY this format (one per learning, separated by blank lines):

FILE: type_short_name.md
NAME: Human-readable title
DESC: One-line description
TYPE: feedback|project|reference|user
BODY:
Content here. For feedback/project types include **Why:** and **How to apply:** lines.
END

Categories:
- feedback: User corrections, preferences, behavioral rules
- project: Architectural decisions, constraints, deadlines
- reference: External systems, URLs, configs, tools
- user: User role, expertise, preferences

Rules:
- Only extract genuinely NEW information not already in existing memories
- Skip generic observations — only save specific, actionable learnings
- If nothing new was learned, output exactly: NONE
- Maximum 3 memories per session" --no-input --model sonnet 2>/dev/null || echo "NONE")

if [ -z "$RESULT" ] || echo "$RESULT" | grep -q "^NONE$"; then
  hook_log "memory-reflect: no new memories to extract"
  emit_event "memory-reflect" "none_found" "allow" "0" 2>/dev/null || true
  exit 0
fi

# Parse and write memory files
CREATED=0
while IFS= read -r line; do
  case "$line" in
    FILE:*)
      FNAME=$(echo "$line" | sed 's/^FILE: *//' | tr -d ' ')
      MNAME="" ; MDESC="" ; MTYPE="" ; MBODY=""
      ;;
    NAME:*) MNAME=$(echo "$line" | sed 's/^NAME: *//') ;;
    DESC:*) MDESC=$(echo "$line" | sed 's/^DESC: *//') ;;
    TYPE:*) MTYPE=$(echo "$line" | sed 's/^TYPE: *//') ;;
    BODY:) CAPTURING=1 ; MBODY="" ;;
    END)
      CAPTURING=""
      if [ -n "$FNAME" ] && [ -n "$MNAME" ] && [ -n "$MTYPE" ]; then
        # Don't overwrite existing files
        if [ ! -f "$MEMORY_DIR/$FNAME" ]; then
          cat > "$MEMORY_DIR/$FNAME" <<MEMEOF
---
name: ${MNAME}
description: ${MDESC}
type: ${MTYPE}
---

${MBODY}
MEMEOF
          # Add to MEMORY.md index
          echo "- [${FNAME}](${FNAME}) — ${MDESC}" >> "$MEMORY_DIR/MEMORY.md"
          CREATED=$((CREATED + 1))
          hook_log "memory-reflect: created $FNAME (type=$MTYPE)"
        fi
      fi
      FNAME="" ; MNAME="" ; MDESC="" ; MTYPE="" ; MBODY=""
      ;;
    *)
      [ "${CAPTURING:-}" = "1" ] && MBODY="${MBODY}${line}
"
      ;;
  esac
done <<< "$RESULT"

hook_log "memory-reflect: created $CREATED new memories"
emit_event "memory-reflect" "memories_created" "allow" "0" "{\"count\":${CREATED}}" 2>/dev/null || true
exit 0
