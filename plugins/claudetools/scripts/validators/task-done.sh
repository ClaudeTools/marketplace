#!/bin/bash
# Validator: task completion verification — checks that work actually matches the task
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = verified done or skipped, 2 = block (not done)

validate_task_done() {
  # Extract task info from hook input
  local TASK_ID TASK_SUBJECT TASK_DESCRIPTION TRANSCRIPT_PATH CWD TEAMMATE TEAM
  TASK_ID=$(hook_get_field '.task_id')
  TASK_SUBJECT=$(hook_get_field '.task_subject')
  TASK_DESCRIPTION=$(hook_get_field '.task_description')
  TRANSCRIPT_PATH=$(hook_get_field '.transcript_path')
  CWD=$(hook_get_field '.cwd' || echo ".")
  TEAMMATE=$(hook_get_field '.teammate_name' || echo "unknown")
  TEAM=$(hook_get_field '.team_name')

  [ -z "$CWD" ] && CWD="."

  # If no task subject, skip (can't verify without knowing the task)
  if [ -z "$TASK_SUBJECT" ]; then
    return 0
  fi

  # --- Deterministic checks first ---

  # 1. Were ANY files actually changed?
  local CHANGED=""
  local CHANGED_COUNT=0
  if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
    CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
    local UNTRACKED
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
    CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')
    CHANGED_COUNT=$(echo "$CHANGED" | grep -c . 2>/dev/null || echo "0")
  fi

  # If zero files changed and task isn't a research/audit task, block
  if [ "$CHANGED_COUNT" -eq 0 ]; then
    case "$TASK_SUBJECT" in
      *[Rr]esearch*|*[Aa]udit*|*[Pp]lan*|*[Rr]eview*|*[Ii]nvestigat*|*[Aa]nalyz*)
        return 0
        ;;
      *)
        cat >&2 <<EOF
No files were changed for this task.

Task: ${TASK_SUBJECT}
Description: ${TASK_DESCRIPTION:-N/A}

Git shows zero changed files. If the work is done, commit your changes first.
If not, implement the task before marking it complete.
EOF
        return 2
        ;;
    esac
  fi

  # 2. Extract the original prompt from the transcript (first user message)
  local ORIGINAL_PROMPT=""
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
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
  local REQUIREMENTS="${TASK_DESCRIPTION:-$TASK_SUBJECT}"
  if [ -n "$ORIGINAL_PROMPT" ]; then
    REQUIREMENTS="ORIGINAL PROMPT:\n${ORIGINAL_PROMPT}\n\nTASK:\n${TASK_DESCRIPTION:-$TASK_SUBJECT}"
  fi

  local VERIFY_PROMPT="You are a strict task completion verifier. Your job: determine if the work matches the requirements.

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

  local RESULT
  RESULT=$(echo "$VERIFY_PROMPT" | timeout 20 claude -p --no-input --model haiku 2>/dev/null || echo "SKIP")

  case "$RESULT" in
    *SKIP*)
      return 0
      ;;
    *NOT_DONE*)
      local REASON
      REASON=$(echo "$RESULT" | head -1)
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
      return 2
      ;;
    *DONE*)
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}
