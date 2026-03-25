#!/bin/bash
# Stop hook (async) — Sonnet-powered memory extraction
# Runs in parallel with session stop. Never blocks.
# Reads session transcript, asks Sonnet to identify learnings,
# writes memory files directly to the project memory directory.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"
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

# Memory directory — use get_repo_root() to handle worktrees correctly.
REPO_ROOT=$(get_repo_root)
MEMORY_DIR="$HOME/.claude/projects/$(echo "$REPO_ROOT" | sed 's|^/|-|; s|/|-|g')/memory"
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

# === PRE-FILTER PIPELINE (deterministic, reduces noise before Sonnet) ===

# Step 1: Extract only USER messages from transcript (highest signal for memories)
RAW_USER_MSGS=$(jq -r '
  if .role == "human" or .role == "user" then
    if (.content | type) == "array" then
      [.content[] | select(type == "string" or .type == "text") |
       if type == "string" then . else .text end] | join(" ")
    else (.content // "") end
  else empty end
' "$TRANSCRIPT" 2>/dev/null || true)
[ -z "$RAW_USER_MSGS" ] && exit 0

# Step 2: Filter out noise — short messages and routine confirmations
FILTERED_MSGS=$(echo "$RAW_USER_MSGS" | while IFS= read -r msg; do
  # Skip empty or very short messages (<15 chars = "ok", "yes", "done", etc.)
  [ ${#msg} -lt 15 ] && continue
  # Skip routine commands and confirmations
  echo "$msg" | grep -qiE '^(ok|yes|no|done|continue|thanks|publish|stop|y|n|sure|go ahead|looks good|lgtm)\s*$' && continue
  # Skip hook feedback messages (system-generated)
  echo "$msg" | grep -qiE '^Stop hook feedback' && continue
  echo "$msg"
done)
[ -z "$FILTERED_MSGS" ] && exit 0

# Step 3: Score and prioritize — messages with correction/decision signal go first
HIGH_SIGNAL=$(echo "$FILTERED_MSGS" | grep -iE "don.t|stop|always|never|wrong|instead|prefer|should|must|change|fix|broken|issue|problem|remember|forget|important|actually|wait|no,|nope" || true)
LOW_SIGNAL=$(echo "$FILTERED_MSGS" | grep -viE "don.t|stop|always|never|wrong|instead|prefer|should|must|change|fix|broken|issue|problem|remember|forget|important|actually|wait|no,|nope" || true)

# Step 4: Build context — high-signal first, then low-signal, capped at 8KB
SESSION_CONTEXT=""
if [ -n "$HIGH_SIGNAL" ]; then
  SESSION_CONTEXT=$(echo "$HIGH_SIGNAL" | head -c 5000 | sed 's/^/[SIGNAL] /')
fi
if [ -n "$LOW_SIGNAL" ]; then
  REMAINING=$((8000 - ${#SESSION_CONTEXT}))
  [ "$REMAINING" -gt 500 ] && SESSION_CONTEXT="${SESSION_CONTEXT}
$(echo "$LOW_SIGNAL" | head -c "$REMAINING")"
fi
[ -z "$SESSION_CONTEXT" ] && exit 0

# Step 5: Count signal density — skip Sonnet call if too little signal
SIGNAL_LINES=$(echo "$HIGH_SIGNAL" | grep -c . 2>/dev/null || echo 0)
TOTAL_LINES=$(echo "$FILTERED_MSGS" | grep -c . 2>/dev/null || echo 0)
if [ "$SIGNAL_LINES" -eq 0 ] && [ "$TOTAL_LINES" -lt 5 ]; then
  hook_log "memory-reflect: low signal density ($SIGNAL_LINES signal, $TOTAL_LINES total), skipping"
  emit_event "memory-reflect" "low_signal" "allow" "0" "{\"signal\":${SIGNAL_LINES},\"total\":${TOTAL_LINES}}" 2>/dev/null || true
  exit 0
fi

hook_log "memory-reflect: ${SIGNAL_LINES} high-signal, ${TOTAL_LINES} total user messages (${#SESSION_CONTEXT} bytes to Sonnet)"

# Existing memories (so we don't duplicate)
EXISTING=""
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  EXISTING=$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true)
fi

hook_log "memory-reflect: invoking Sonnet for memory extraction"

# Call Sonnet via claude CLI with a focused extraction prompt
RESULT=$(echo "$SESSION_CONTEXT" | timeout 45 claude -p "You are a memory extraction agent. Review this session transcript and identify NEW learnings worth saving for future sessions.

<existing_memories>
${EXISTING}
</existing_memories>

ALWAYS check existing memories before creating new ones. NEVER duplicate an existing memory — update it instead.

<output_format>
For each new learning, output EXACTLY this format (one per learning, separated by blank lines):

FILE: type_short_name.md
NAME: Human-readable title
DESC: One-line description
TYPE: feedback|project|reference|user
BODY:
Content here. For feedback/project types include **Why:** and **How to apply:** lines.
END

WRONG: FILE: general_notes.md with vague content like 'Be careful with deployments'
CORRECT: FILE: feedback_no_force_push.md with specific actionable rule like 'Never use git push --force on shared branches — use --force-with-lease instead'
</output_format>

<extraction_rules>
Categories:
- feedback: User corrections, preferences, behavioral rules
- project: Architectural decisions, constraints, deadlines
- reference: External systems, URLs, configs, tools
- user: User role, expertise, preferences

Rules:
- Only extract genuinely NEW information not already in existing memories
- Skip generic observations — only save specific, actionable learnings
- If nothing new was learned, output exactly: NONE
- Maximum 3 memories per session

CRITICAL: Every memory MUST be grounded in a direct quote from the transcript. Include the quote in the memory body. If you cannot find a supporting quote, do NOT create that memory. Ungrounded memories pollute the memory system.
</extraction_rules>" --no-input --model sonnet 2>/dev/null || echo "NONE")

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

# === PHASE 2: Negative-pattern extraction ===
# Formerly session-learn-negatives.sh — identifies mistakes, corrections, failed approaches.

# Build negative-signal context: tool errors, user corrections, hook blocks
ERRORS=$(jq -r '
  select(.role == "assistant") |
  .content // [] |
  if type == "array" then
    [.[] | select(.type == "tool_result") |
     select(.is_error == true or (.content // "" | test("error|fail|exception|denied"; "i"))) |
     .content // ""] | .[]
  else empty end
' "$TRANSCRIPT" 2>/dev/null | tail -20 | head -c 2000 || true)

CORRECTIONS=$(echo "$RAW_USER_MSGS" | grep -iE "(no[, ]+not|don't|do not|instead[, ]+use|actually[, ]|stop doing|wrong|shouldn't|that's not|please don't|never)" 2>/dev/null | head -c 1500 || true)

LOG_FILE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/logs/hooks.log"
HOOK_BLOCKS=""
if [ -f "$LOG_FILE" ]; then
  HOOK_BLOCKS=$(grep -E "decision=(block|reject|warn)" "$LOG_FILE" 2>/dev/null | tail -15 | head -c 1000 || true)
fi

# Skip negative extraction if no negative signals found
NEG_TOTAL="${ERRORS}${CORRECTIONS}${HOOK_BLOCKS}"
if [ ${#NEG_TOTAL} -lt 50 ]; then
  hook_log "memory-reflect: no negative signals found, skipping phase 2"
  exit 0
fi

hook_log "memory-reflect: phase 2 — extracting negative patterns with Sonnet"

NEG_CONTEXT="SESSION NEGATIVE REVIEW

User corrections:
${CORRECTIONS:-None detected}

Tool errors/failures:
${ERRORS:-None detected}

Hook blocks/warnings:
${HOOK_BLOCKS:-None}"

NEG_RESULT=$(echo "$NEG_CONTEXT" | timeout 45 claude -p --model sonnet \
  "You are reviewing a Claude Code session to extract NEGATIVE learnings — mistakes made, corrections received, approaches that failed.

<output_format>
For each finding, output EXACTLY this format (one per line, no other text):
TYPE|SLUG|DESCRIPTION|WHY|HOW_TO_APPLY

Where:
- TYPE: feedback, project, or user
- SLUG: kebab-case identifier for the filename
- DESCRIPTION: one-line summary
- WHY: why this happened or why it matters
- HOW_TO_APPLY: what to do differently next time

If nothing significant went wrong, output exactly: NONE
Maximum 3 findings per session. Only HIGH-CONFIDENCE findings grounded in actual session evidence.
</output_format>" 2>/dev/null || true)

if [ -z "$NEG_RESULT" ] || [ "$NEG_RESULT" = "NONE" ]; then
  hook_log "memory-reflect: phase 2 — no negative patterns found"
  exit 0
fi

NEG_CREATED=0
while IFS='|' read -r TYPE SLUG DESCRIPTION WHY HOW_TO_APPLY; do
  [ -z "$TYPE" ] || [ -z "$SLUG" ] || [ -z "$DESCRIPTION" ] && continue
  [ "$TYPE" = "NONE" ] && continue

  SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | head -c 50)
  [ -z "$SLUG" ] && continue

  FILENAME="${TYPE}_${SLUG}.md"
  FILEPATH="$MEMORY_DIR/$FILENAME"

  # Skip if memory already exists
  [ -f "$FILEPATH" ] && continue

  cat > "$FILEPATH" <<NEGMEMEOF
---
name: ${DESCRIPTION}
description: ${DESCRIPTION}
type: ${TYPE}
---

${DESCRIPTION}

**Why:** ${WHY:-No context provided}

**How to apply:** ${HOW_TO_APPLY:-Avoid this pattern in future sessions}
NEGMEMEOF

  if [ -f "$MEMORY_DIR/MEMORY.md" ] && ! grep -qF "$FILENAME" "$MEMORY_DIR/MEMORY.md" 2>/dev/null; then
    echo "- [${FILENAME}](${FILENAME}) — ${DESCRIPTION}" >> "$MEMORY_DIR/MEMORY.md"
  fi

  NEG_CREATED=$((NEG_CREATED + 1))
  hook_log "memory-reflect: phase 2 — created negative memory $FILENAME"
done <<< "$NEG_RESULT"

hook_log "memory-reflect: phase 2 — created $NEG_CREATED negative-pattern memories"
exit 0
