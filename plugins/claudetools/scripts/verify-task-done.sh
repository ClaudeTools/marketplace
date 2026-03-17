#!/bin/bash
# TaskCompleted hook — "Have you actually done this though?"
# Reads the task subject + description (which contains the original prompt-improver requirements)
# Checks changed files against the task requirements
# Exit 2 + stderr = BLOCKS completion, feeds feedback to agent, agent MUST continue working
# Exit 0 = allows completion

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract task info from hook input
TASK_ID=$(echo "$INPUT" | jq -r '.task_id // empty' 2>/dev/null || true)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null || true)
TASK_DESCRIPTION=$(echo "$INPUT" | jq -r '.task_description // empty' 2>/dev/null || true)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || true)
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null || true)
TEAM=$(echo "$INPUT" | jq -r '.team_name // empty' 2>/dev/null || true)

# If no task subject, skip (can't verify without knowing the task)
if [ -z "$TASK_SUBJECT" ]; then
  hook_log "no task_subject, skipping"
  exit 0
fi

# --- Deterministic checks first ---

# 1. Were ANY files actually changed?
CHANGED=""
CHANGED_COUNT=0
if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
  CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
  UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
  CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')
  CHANGED_COUNT=$(echo "$CHANGED" | grep -c . 2>/dev/null || echo "0")
fi

# If zero files changed and task isn't a research/audit task, block
if [ "$CHANGED_COUNT" -eq 0 ]; then
  # Allow through for research/audit/plan tasks (they may not produce file changes)
  case "$TASK_SUBJECT" in
    *[Rr]esearch*|*[Aa]udit*|*[Pp]lan*|*[Rr]eview*|*[Ii]nvestigat*|*[Aa]nalyz*)
      hook_log "research/audit task with no file changes, allowing"
      exit 0
      ;;
    *)
      HOOK_DECISION="reject" HOOK_REASON="zero files changed for implementation task"
      cat >&2 <<EOF
No files were changed for this task.

Task: ${TASK_SUBJECT}
Description: ${TASK_DESCRIPTION:-N/A}

Git shows zero changed files. If the work is done, commit your changes first.
If not, implement the task before marking it complete.
EOF
      exit 2
      ;;
  esac
fi

# 2. Extract the original prompt from the transcript (first user message)
ORIGINAL_PROMPT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Get the first user message — this is the original prompt/requirements
  ORIGINAL_PROMPT=$(head -100 "$TRANSCRIPT_PATH" 2>/dev/null \
    | grep '"role":"user"' 2>/dev/null \
    | head -1 \
    | python3 -c "
import sys, json
try:
    line = sys.stdin.read().strip()
    if line:
        d = json.loads(line)
        content = d.get('message',{}).get('content','')
        if isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get('type') == 'text':
                    print(c.get('text','')[:2000])
                    break
                elif isinstance(c, str):
                    print(c[:2000])
                    break
        elif isinstance(content, str):
            print(content[:2000])
except: pass
" 2>/dev/null || true)
fi

# 3. AI verification — compare task requirements against actual work
# Use the task description (which prompt-improver fills with the full requirements)
# AND the original prompt if available
REQUIREMENTS="${TASK_DESCRIPTION:-$TASK_SUBJECT}"
if [ -n "$ORIGINAL_PROMPT" ]; then
  REQUIREMENTS="ORIGINAL PROMPT:\n${ORIGINAL_PROMPT}\n\nTASK:\n${TASK_DESCRIPTION:-$TASK_SUBJECT}"
fi

VERIFY_PROMPT="You are a strict task completion verifier. Your job: determine if the work matches the requirements.

REQUIREMENTS:
${REQUIREMENTS}

FILES CHANGED (${CHANGED_COUNT} files):
$(echo "$CHANGED" | head -30)

RULES:
- If the requirements describe specific features/fixes and the changed files plausibly implement them: DONE
- If zero relevant files changed: NOT_DONE
- If the changes look like a different task entirely: NOT_DONE
- If only config/docs changed for an implementation task: NOT_DONE
- Be strict. The agent claims this is done. Verify it.

Answer ONLY: DONE or NOT_DONE followed by a one-sentence reason."

RESULT=$(echo "$VERIFY_PROMPT" | timeout 20 claude -p --no-input --model haiku 2>/dev/null || echo "SKIP")

case "$RESULT" in
  *SKIP*)
    hook_log "AI verification skipped (timeout/unavailable)"
    exit 0
    ;;
  *NOT_DONE*)
    REASON=$(echo "$RESULT" | head -1)
    HOOK_DECISION="reject" HOOK_REASON="$REASON"
    cat >&2 <<EOF
Work does not match the task requirements.

Task: ${TASK_SUBJECT}
Verification: ${REASON}

Original requirements:
${TASK_DESCRIPTION:-$TASK_SUBJECT}

Files changed: ${CHANGED_COUNT}
$(echo "$CHANGED" | head -15)

Re-read the requirements above. If something is missing, implement it before marking complete.
EOF
    exit 2
    ;;
  *DONE*)
    hook_log "task verified as done"
    exit 0
    ;;
  *)
    hook_log "unexpected result: $RESULT"
    exit 0
    ;;
esac
