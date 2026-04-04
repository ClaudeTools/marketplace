#!/usr/bin/env bash
# memory-combined.sh — Stop hook (async)
# Combined deterministic extraction + AI reflection in one pass.
#
# Phase 1 (deterministic): ALWAYS runs — extracts candidates and saves to JSONL.
#                           Never lost to timeout. Sets HIGH_SIGNAL if any found.
# Phase 2 (AI):            Only runs if high-signal candidates found, claude CLI
#                           is available, and session is longer than 5 minutes.

set -euo pipefail

[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-input.sh"
hook_init

source "${SCRIPT_DIR}/lib/worktree.sh"
source "${SCRIPT_DIR}/lib/portable-lock.sh"
source "${SCRIPT_DIR}/lib/telemetry.sh" 2>/dev/null || true

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
[[ -z "$CWD" ]] && CWD="."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PLUGIN_DATA="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}/data"
mkdir -p "$PLUGIN_DATA" 2>/dev/null || true
CANDIDATES_FILE="$PLUGIN_DATA/memory-candidates.jsonl"

# ============================================================
# PHASE 1 — Deterministic extraction (always runs)
# ============================================================

HIGH_SIGNAL=0

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  hook_log "memory-combined: no transcript found, skipping"
  exit 0
fi

hook_log "memory-combined: phase 1 — processing $TRANSCRIPT"

TAIL_CONTENT=$(tail -100 "$TRANSCRIPT" 2>/dev/null || true)
if [[ -z "$TAIL_CONTENT" ]]; then
  hook_log "memory-combined: empty tail content, skipping"
  exit 0
fi

# Helper: append a candidate to the JSONL file with locking
emit_candidate() {
  local ctype="$1"
  local desc="$2"
  desc=$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 200)
  local entry="{\"type\":\"$ctype\",\"description\":\"$desc\",\"source\":\"stop-extract\",\"session_id\":\"$SESSION_ID\",\"timestamp\":\"$TIMESTAMP\"}"
  if portable_lock "${CANDIDATES_FILE}.lock"; then
    echo "$entry" >> "$CANDIDATES_FILE" 2>/dev/null || true
    portable_unlock "${CANDIDATES_FILE}.lock"
  else
    echo "$entry" >> "$CANDIDATES_FILE" 2>/dev/null || true
  fi
  HIGH_SIGNAL=1
}

# --- Extract user corrections ---
while IFS= read -r msg; do
  [[ -z "$msg" ]] && continue
  if echo "$msg" | grep -qiE "\b(no[, ]+not|don't|do not|instead[, ]+use|actually[, ]|stop doing|wrong|shouldn't|that's not|please don't|never|prefer|always)"; then
    emit_candidate "correction" "$msg"
  fi
done < <(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "human" or .role == "user") |
  .content // .message // "" |
  if type == "array" then
    map(select(type == "string" or .type == "text") |
      if type == "string" then . else .text end) | join(" ")
  else . end
' 2>/dev/null || true)

# --- Extract error patterns ---
while IFS= read -r err; do
  [[ -z "$err" ]] && continue
  emit_candidate "error" "$err"
done < <(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") |
  .content // "" |
  if type == "array" then
    map(select(.type == "tool_result" or .type == "text") |
      if .type == "tool_result" then (.content // "") else (.text // "") end) | join(" ")
  else . end
' 2>/dev/null | grep -iE '(error|exception|failed|traceback|panic|ENOENT|EACCES|permission denied)' 2>/dev/null | head -5 || true)

# --- Detect file churn (files edited >=3 times) ---
EDIT_COUNTS=$(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") | .content // [] |
  if type == "array" then .[] else empty end |
  select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) |
  .input.file_path // .input.path // empty
' 2>/dev/null | sort | uniq -c | sort -rn || true)

if [[ -n "$EDIT_COUNTS" ]]; then
  while read -r count filepath; do
    if [[ "$count" -ge 3 && -n "$filepath" ]]; then
      emit_candidate "churn" "File edited $count times in session: $filepath"
    fi
  done <<< "$EDIT_COUNTS"
fi

CANDIDATE_COUNT=$(wc -l < "$CANDIDATES_FILE" 2>/dev/null | tr -d ' ' || echo 0)
hook_log "memory-combined: phase 1 done — HIGH_SIGNAL=$HIGH_SIGNAL (total candidates in file: $CANDIDATE_COUNT)"

# ============================================================
# PHASE 2 — AI reflection (conditional)
# ============================================================

# Skip if no high-signal candidates found in this session
if [[ "$HIGH_SIGNAL" -eq 0 ]]; then
  hook_log "memory-combined: phase 2 skipped — no high-signal candidates"
  exit 0
fi

# Skip if claude CLI not available
if ! command -v claude &>/dev/null; then
  hook_log "memory-combined: phase 2 skipped — claude CLI not found"
  exit 0
fi

# Skip if session is shorter than 5 minutes
START_MARKER="/tmp/.claude-session-start-${SESSION_ID}"
if [[ -f "$START_MARKER" ]]; then
  START_TIME=$(stat -c '%Y' "$START_MARKER" 2>/dev/null || stat -f '%m' "$START_MARKER" 2>/dev/null || echo 0)
  NOW_TIME=$(date +%s)
  SESSION_AGE_MIN=$(( (NOW_TIME - START_TIME) / 60 ))
  if [[ "$SESSION_AGE_MIN" -lt 5 ]]; then
    hook_log "memory-combined: phase 2 skipped — session too short (${SESSION_AGE_MIN} min)"
    exit 0
  fi
fi

# Memory directory — use get_repo_root() to handle worktrees correctly
REPO_ROOT=$(get_repo_root)
MEMORY_DIR="$HOME/.claude/projects/$(echo "$REPO_ROOT" | sed 's|^/|-|; s|/|-|g')/memory"
mkdir -p "$MEMORY_DIR" 2>/dev/null || exit 0

# Check if memories were already saved this session
if [[ -f "$START_MARKER" ]]; then
  NEW_MEMORIES=$(find "$MEMORY_DIR" -name "*.md" -newer "$START_MARKER" -not -name "MEMORY.md" -not -name "auto_session_summary.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$NEW_MEMORIES" -gt 0 ]]; then
    hook_log "memory-combined: phase 2 skipped — ${NEW_MEMORIES} memories already saved this session"
    emit_event "memory-combined" "already_saved" "allow" "0" "{\"count\":${NEW_MEMORIES}}" 2>/dev/null || true
    exit 0
  fi
fi

hook_log "memory-combined: phase 2 — starting AI reflection"

# Extract user messages from full transcript, filter noise
RAW_USER_MSGS=$(jq -r '
  if .role == "human" or .role == "user" then
    if (.content | type) == "array" then
      [.content[] | select(type == "string" or .type == "text") |
       if type == "string" then . else .text end] | join(" ")
    else (.content // "") end
  else empty end
' "$TRANSCRIPT" 2>/dev/null || true)

if [[ -z "$RAW_USER_MSGS" ]]; then
  hook_log "memory-combined: phase 2 skipped — no user messages in transcript"
  exit 0
fi

# Filter out noise: short messages and routine confirmations
FILTERED_MSGS=$(echo "$RAW_USER_MSGS" | while IFS= read -r msg; do
  [[ ${#msg} -lt 15 ]] && continue
  echo "$msg" | grep -qiE '^(ok|yes|no|done|continue|thanks|publish|stop|y|n|sure|go ahead|looks good|lgtm)\s*$' && continue
  echo "$msg" | grep -qiE '^Stop hook feedback' && continue
  echo "$msg"
done)

if [[ -z "$FILTERED_MSGS" ]]; then
  hook_log "memory-combined: phase 2 skipped — all user messages filtered as noise"
  exit 0
fi

# Score: high-signal messages first, then low-signal, capped at 8KB
HIGH_SIGNAL_MSGS=$(echo "$FILTERED_MSGS" | grep -iE "don.t|stop|always|never|wrong|instead|prefer|should|must|change|fix|broken|issue|problem|remember|forget|important|actually|wait|no,|nope" || true)
LOW_SIGNAL_MSGS=$(echo "$FILTERED_MSGS" | grep -viE "don.t|stop|always|never|wrong|instead|prefer|should|must|change|fix|broken|issue|problem|remember|forget|important|actually|wait|no,|nope" || true)

SESSION_CONTEXT=""
if [[ -n "$HIGH_SIGNAL_MSGS" ]]; then
  SESSION_CONTEXT=$(echo "$HIGH_SIGNAL_MSGS" | head -c 5000 | sed 's/^/[SIGNAL] /')
fi
if [[ -n "$LOW_SIGNAL_MSGS" ]]; then
  REMAINING=$((8000 - ${#SESSION_CONTEXT}))
  [[ "$REMAINING" -gt 500 ]] && SESSION_CONTEXT="${SESSION_CONTEXT}
$(echo "$LOW_SIGNAL_MSGS" | head -c "$REMAINING")"
fi

if [[ -z "$SESSION_CONTEXT" ]]; then
  hook_log "memory-combined: phase 2 skipped — empty session context after scoring"
  exit 0
fi

# Check signal density threshold
SIGNAL_LINES=$(echo "$HIGH_SIGNAL_MSGS" | grep -c . 2>/dev/null || echo 0)
TOTAL_LINES=$(echo "$FILTERED_MSGS" | grep -c . 2>/dev/null || echo 0)
if [[ "$SIGNAL_LINES" -eq 0 && "$TOTAL_LINES" -lt 5 ]]; then
  hook_log "memory-combined: phase 2 skipped — low signal density ($SIGNAL_LINES signal, $TOTAL_LINES total)"
  emit_event "memory-combined" "low_signal" "allow" "0" "{\"signal\":${SIGNAL_LINES},\"total\":${TOTAL_LINES}}" 2>/dev/null || true
  exit 0
fi

hook_log "memory-combined: phase 2 — ${SIGNAL_LINES} high-signal, ${TOTAL_LINES} total user messages (${#SESSION_CONTEXT} bytes to Sonnet)"

EXISTING=""
if [[ -f "$MEMORY_DIR/MEMORY.md" ]]; then
  EXISTING=$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true)
fi

# Call Sonnet for positive memory extraction
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

CREATED=0
if [[ -z "$RESULT" ]] || echo "$RESULT" | grep -q "^NONE$"; then
  hook_log "memory-combined: phase 2 — no new positive memories to extract"
else
  FNAME="" ; MNAME="" ; MDESC="" ; MTYPE="" ; MBODY="" ; CAPTURING=""
  while IFS= read -r line; do
    case "$line" in
      FILE:*)
        FNAME=$(echo "$line" | sed 's/^FILE: *//' | tr -d ' ')
        MNAME="" ; MDESC="" ; MTYPE="" ; MBODY="" ; CAPTURING=""
        ;;
      NAME:*) MNAME=$(echo "$line" | sed 's/^NAME: *//') ;;
      DESC:*)  MDESC=$(echo "$line" | sed 's/^DESC: *//') ;;
      TYPE:*)  MTYPE=$(echo "$line" | sed 's/^TYPE: *//') ;;
      BODY:)   CAPTURING=1 ; MBODY="" ;;
      END)
        CAPTURING=""
        if [[ -n "$FNAME" && -n "$MNAME" && -n "$MTYPE" ]]; then
          if [[ ! -f "$MEMORY_DIR/$FNAME" ]]; then
            cat > "$MEMORY_DIR/$FNAME" <<MEMEOF
---
name: ${MNAME}
description: ${MDESC}
type: ${MTYPE}
---

${MBODY}
MEMEOF
            echo "- [${FNAME}](${FNAME}) — ${MDESC}" >> "$MEMORY_DIR/MEMORY.md"
            CREATED=$((CREATED + 1))
            hook_log "memory-combined: created $FNAME (type=$MTYPE)"
          fi
        fi
        FNAME="" ; MNAME="" ; MDESC="" ; MTYPE="" ; MBODY="" ; CAPTURING=""
        ;;
      *)
        [[ "${CAPTURING:-}" = "1" ]] && MBODY="${MBODY}${line}
"
        ;;
    esac
  done <<< "$RESULT"
fi

hook_log "memory-combined: phase 2 — created $CREATED positive memories"
emit_event "memory-combined" "memories_created" "allow" "0" "{\"count\":${CREATED}}" 2>/dev/null || true

# --- Negative-pattern extraction ---
# Build negative-signal context: user corrections + tool errors + hook blocks

RAW_CORRECTIONS=$(jq -r '
  if .role == "human" or .role == "user" then
    if (.content | type) == "array" then
      [.content[] | select(type == "string" or .type == "text") |
       if type == "string" then . else .text end] | join(" ")
    else (.content // "") end
  else empty end
' "$TRANSCRIPT" 2>/dev/null || true)

CORRECTIONS=$(echo "$RAW_CORRECTIONS" | grep -iE "(no[, ]+not|don't|do not|instead[, ]+use|actually[, ]|stop doing|wrong|shouldn't|that's not|please don't|never)" 2>/dev/null | head -c 1500 || true)

ERRORS=$(jq -r '
  select(.role == "assistant") |
  .content // [] |
  if type == "array" then
    [.[] | select(.type == "tool_result") |
     select(.is_error == true or (.content // "" | test("error|fail|exception|denied"; "i"))) |
     .content // ""] | .[]
  else empty end
' "$TRANSCRIPT" 2>/dev/null | tail -20 | head -c 2000 || true)

LOG_FILE="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}/logs/hooks.log"
HOOK_BLOCKS=""
if [[ -f "$LOG_FILE" ]]; then
  HOOK_BLOCKS=$(grep -E "decision=(block|reject|warn)" "$LOG_FILE" 2>/dev/null | tail -15 | head -c 1000 || true)
fi

NEG_TOTAL="${ERRORS}${CORRECTIONS}${HOOK_BLOCKS}"
if [[ ${#NEG_TOTAL} -lt 50 ]]; then
  hook_log "memory-combined: phase 2 — no negative signals found, done"
  exit 0
fi

hook_log "memory-combined: phase 2 — extracting negative patterns with Sonnet"

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

if [[ -z "$NEG_RESULT" || "$NEG_RESULT" = "NONE" ]]; then
  hook_log "memory-combined: phase 2 — no negative patterns found"
  exit 0
fi

NEG_CREATED=0
while IFS='|' read -r TYPE SLUG DESCRIPTION WHY HOW_TO_APPLY; do
  [[ -z "$TYPE" || -z "$SLUG" || -z "$DESCRIPTION" ]] && continue
  [[ "$TYPE" = "NONE" ]] && continue

  SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | head -c 50)
  [[ -z "$SLUG" ]] && continue

  FILENAME="${TYPE}_${SLUG}.md"
  FILEPATH="$MEMORY_DIR/$FILENAME"
  [[ -f "$FILEPATH" ]] && continue

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

  if [[ -f "$MEMORY_DIR/MEMORY.md" ]] && ! grep -qF "$FILENAME" "$MEMORY_DIR/MEMORY.md" 2>/dev/null; then
    echo "- [${FILENAME}](${FILENAME}) — ${DESCRIPTION}" >> "$MEMORY_DIR/MEMORY.md"
  fi

  NEG_CREATED=$((NEG_CREATED + 1))
  hook_log "memory-combined: phase 2 — created negative memory $FILENAME"
done <<< "$NEG_RESULT"

hook_log "memory-combined: phase 2 — created $NEG_CREATED negative-pattern memories"
exit 0
