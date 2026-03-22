#!/usr/bin/env bash
# session-learn-negatives.sh — Stop hook (async)
# Uses Sonnet 4.6 to review the session and extract negative patterns,
# mistakes, and corrections. Writes findings directly as native memory files.
# Graceful degradation: skips if claude CLI or transcript unavailable.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)

# Require claude CLI
if ! command -v claude &>/dev/null; then
  hook_log "session-learn-negatives: claude CLI not found, skipping"
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date +"%Y-%m-%d")

# Need a transcript to analyse
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  hook_log "session-learn-negatives: no transcript found"
  exit 0
fi

# Memory directory — use native Claude Code memory path
MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
if [[ ! -d "$MEMORY_DIR" ]]; then
  hook_log "session-learn-negatives: no memory dir at $MEMORY_DIR, skipping"
  exit 0
fi

hook_log "session-learn-negatives: analysing session with Sonnet 4.6"

# Build a rich session summary — include tool failures, user corrections, and recent diffs
# 1. User messages (full text, not truncated to 300 chars)
USER_MSGS=$(jq -r '
  select(.role == "human" or .role == "user") |
  .content // .message // "" |
  if type == "array" then
    [.[] | select(type == "string" or .type == "text") |
     if type == "string" then . else .text end] | join(" ")
  else . end
' "$TRANSCRIPT" 2>/dev/null | tail -40 | head -c 4000 || true)

# 2. Tool failures and errors
ERRORS=$(jq -r '
  select(.role == "assistant") |
  .content // [] |
  if type == "array" then
    [.[] | select(.type == "tool_result") |
     select(.is_error == true or (.content // "" | test("error|fail|exception|denied"; "i"))) |
     .content // ""] | .[]
  else empty end
' "$TRANSCRIPT" 2>/dev/null | tail -20 | head -c 2000 || true)

# 3. User corrections (messages with correction indicators)
CORRECTIONS=$(echo "$USER_MSGS" | grep -iE "(no[, ]+not|don't|do not|instead[, ]+use|actually[, ]|stop doing|wrong|shouldn't|that's not|please don't|never)" 2>/dev/null | head -c 1500 || true)

# 4. Hook log negatives (blocks and warnings from this session)
LOG_FILE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/logs/hooks.log"
HOOK_BLOCKS=""
if [[ -f "$LOG_FILE" ]]; then
  HOOK_BLOCKS=$(grep -E "decision=(block|reject|warn)" "$LOG_FILE" 2>/dev/null | tail -15 | head -c 1000 || true)
fi

# 5. Git diff summary (what was actually changed)
DIFF_SUMMARY=""
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
  DIFF_SUMMARY=$(git -C "$CWD" diff --stat HEAD~3..HEAD 2>/dev/null | tail -10 | head -c 500 || true)
fi

# Skip if session was too short for meaningful analysis
TOTAL_CONTENT="${USER_MSGS}${ERRORS}${CORRECTIONS}"
if [[ ${#TOTAL_CONTENT} -lt 100 ]]; then
  hook_log "session-learn-negatives: session too short for analysis"
  exit 0
fi

# Escape for passing to claude CLI
CONTEXT=$(cat <<ENDCONTEXT
SESSION REVIEW — Extract negative learnings

User messages (recent):
$USER_MSGS

Tool errors/failures:
${ERRORS:-None detected}

User corrections:
${CORRECTIONS:-None detected}

Hook blocks/warnings:
${HOOK_BLOCKS:-None}

Files changed:
${DIFF_SUMMARY:-No git changes}
ENDCONTEXT
)

# Call Sonnet 4.6 via claude CLI
RESPONSE=$(echo "$CONTEXT" | timeout 45 claude -p --model claude-sonnet-4-6 \
  "You are reviewing a Claude Code session to extract NEGATIVE learnings — mistakes made, corrections received, approaches that failed, anti-patterns observed.

Your job is to identify things that went WRONG or were CORRECTED so future sessions avoid repeating them.

The session data is provided via stdin in <session_data> format.

<detection_categories>
1. USER CORRECTIONS: User explicitly told the agent to stop, change approach, or do something differently
2. FAILED APPROACHES: Tool calls that failed, required multiple retries, or had to be abandoned
3. ANTI-PATTERNS: Approaches that wasted time, created unnecessary complexity, or violated project conventions
4. WRONG ASSUMPTIONS: Things the agent assumed that turned out to be incorrect
</detection_categories>

<output_format>
For each finding, output EXACTLY this format (one per line, no other text):
TYPE|SLUG|DESCRIPTION|WHY|HOW_TO_APPLY

Where:
- TYPE: feedback, project, or user (matching Claude Code memory types)
- SLUG: kebab-case identifier for the filename (e.g., avoid-direct-db-queries)
- DESCRIPTION: one-line summary for the memory file frontmatter
- WHY: why this happened or why it matters
- HOW_TO_APPLY: what to do differently next time

WRONG: feedback|general-improvement|Should be more careful|Seems like issues occurred|Be more careful
CORRECT: feedback|avoid-force-push|Never use git push --force on shared branches|User said \"don't force push, you'll overwrite my changes\"|Check if branch has upstream before pushing; use --force-with-lease instead

If nothing significant went wrong, output exactly: NONE
Output ONLY the findings or NONE. No explanations, no commentary.
</output_format>

<extraction_rules>
- Base findings ONLY on evidence visible in the session data. NEVER infer problems that aren't explicitly shown.
- Every finding MUST reference a specific user message, error, or hook block from the session data.
- Only output HIGH-CONFIDENCE findings (things clearly wrong, not ambiguous)
- Maximum 3 findings per session
- Skip trivial issues (typos, minor style preferences)
- Skip things already captured in CLAUDE.md or existing memory files
</extraction_rules>" 2>/dev/null || true)

if [[ -z "$RESPONSE" || "$RESPONSE" == "NONE" ]]; then
  hook_log "session-learn-negatives: no negative patterns found"
  exit 0
fi

# Parse response and create memory files
CREATED=0
while IFS='|' read -r TYPE SLUG DESCRIPTION WHY HOW_TO_APPLY; do
  # Validate fields
  [[ -z "$TYPE" || -z "$SLUG" || -z "$DESCRIPTION" ]] && continue
  [[ "$TYPE" == "NONE" ]] && continue

  # Sanitise slug for filename
  SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | head -c 50)
  [[ -z "$SLUG" ]] && continue

  # Build memory filename
  FILENAME="${TYPE}_${SLUG}.md"
  FILEPATH="$MEMORY_DIR/$FILENAME"

  # Skip if memory already exists
  if [[ -f "$FILEPATH" ]]; then
    hook_log "session-learn-negatives: skipping existing memory $FILENAME"
    continue
  fi

  # Write the memory file with YAML frontmatter
  cat > "$FILEPATH" <<ENDMEMORY
---
name: ${DESCRIPTION}
description: ${DESCRIPTION}
type: ${TYPE}
---

${DESCRIPTION}

**Why:** ${WHY:-No context provided}

**How to apply:** ${HOW_TO_APPLY:-Avoid this pattern in future sessions}
ENDMEMORY

  # Add to MEMORY.md index
  if [[ -f "$MEMORY_DIR/MEMORY.md" ]]; then
    # Check if already in index
    if ! grep -qF "$FILENAME" "$MEMORY_DIR/MEMORY.md" 2>/dev/null; then
      echo "- [${FILENAME}](${FILENAME}) — ${DESCRIPTION}" >> "$MEMORY_DIR/MEMORY.md"
    fi
  fi

  CREATED=$((CREATED + 1))
  hook_log "session-learn-negatives: created memory $FILENAME"
done <<< "$RESPONSE"

hook_log "session-learn-negatives: created $CREATED negative-pattern memories"
exit 0
