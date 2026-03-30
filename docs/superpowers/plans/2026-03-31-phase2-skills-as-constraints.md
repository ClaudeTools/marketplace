# Phase 2: Skills as Constraints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shift from reactive enforcement to proactive constraints by adding mandatory skill invocation via intent classification at UserPromptSubmit, and merge the 3-level memory system to 2 levels.

**Architecture:** Extend the existing `inject-prompt-context.sh` hook with a Tier 1 keyword classifier that maps user prompts to skills. Merge `memory-extract-fast.sh` and `memory-reflect.sh` into a single async Stop hook that runs deterministic extraction first (never lost), then conditionally invokes AI reflection.

**Tech Stack:** Bash, jq, YAML frontmatter parsing

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/scripts/inject-prompt-context.sh` | Modify: add intent classification after STOP detection |
| `plugin/scripts/lib/skill-router.sh` | Create: Tier 1 keyword-to-skill mapping library |
| `plugin/scripts/memory-combined.sh` | Create: merged memory extraction + reflection hook |
| `plugin/scripts/memory-extract-fast.sh` | Delete: replaced by memory-combined.sh |
| `plugin/scripts/memory-reflect.sh` | Delete: replaced by memory-combined.sh |
| `plugin/hooks/hooks.json` | Modify: replace 2 memory hooks with 1 combined hook |

---

### Task 1: Create lib/skill-router.sh — Tier 1 intent classifier

**Files:**
- Create: `plugin/scripts/lib/skill-router.sh`

- [ ] **Step 1: Create the skill routing library**

```bash
#!/usr/bin/env bash
# skill-router.sh — Tier 1 keyword-based intent classification
# Maps user prompts to skill names using deterministic pattern matching.
# Returns empty string if no skill matches (Tier 2/3 would handle, but we don't have those yet).

# classify_intent TEXT → echoes skill name or empty
classify_intent() {
  local text="${1:-}"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  # Priority order: most specific first, broadest last
  # Debug/fix patterns → debugger
  case "$lower" in
    *debug*|*"fix this"*|*"fix the"*|*"why is"*failing*|*"not working"*|*broken*|*"unexpected behav"*|*error*)
      echo "debugger"; return 0 ;;
  esac

  # Frontend/UI patterns → frontend-design
  case "$lower" in
    *"landing page"*|*dashboard*|*"web app"*|*"ui component"*|*"dark mode"*|*"design system"*|*redesign*|*restyle*)
      echo "frontend-design"; return 0 ;;
  esac

  # Prompt engineering → prompt-improver
  case "$lower" in
    *"improve prompt"*|*"prompt engineer"*|*"structure a prompt"*|*"/prompt-improver"*)
      echo "prompt-improver"; return 0 ;;
  esac

  # Code review → code-review
  case "$lower" in
    *"review code"*|*"code review"*|*"review the"*|*"audit code"*|*"check quality"*)
      echo "code-review"; return 0 ;;
  esac

  # Exploration → codebase-explorer
  case "$lower" in
    *"where is"*defined*|*"find where"*|*"trace the"*|*"how does"*work*|*"explore the"*code*)
      echo "codebase-explorer"; return 0 ;;
  esac

  # Plugin self-improvement → plugin-improver
  case "$lower" in
    *"improve plugin"*|*"self-improve"*|*"improvement loop"*|*"/plugin-improver"*)
      echo "plugin-improver"; return 0 ;;
  esac

  # No match — no skill injection
  echo ""
  return 0
}

# format_skill_hint SKILL_NAME → echoes a context injection string
format_skill_hint() {
  local skill="${1:-}"
  [ -z "$skill" ] && return 0
  echo "[skill-hint] The /$skill skill is relevant to this task. Invoke it before starting work."
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n plugin/scripts/lib/skill-router.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/lib/skill-router.sh
git commit -m "feat: add Tier 1 skill intent classifier (lib/skill-router.sh)

Deterministic keyword-based routing that maps user prompts to skills.
Zero tokens, sub-millisecond. Covers debugger, frontend-design,
prompt-improver, code-review, codebase-explorer, plugin-improver."
```

---

### Task 2: Wire skill-router into inject-prompt-context.sh

**Files:**
- Modify: `plugin/scripts/inject-prompt-context.sh`

- [ ] **Step 1: Read the current file**

Run: `cat -n plugin/scripts/inject-prompt-context.sh`
Note the line numbers for: end of STOP detection block, start of mesh inbox check.

- [ ] **Step 2: Add skill routing between STOP detection and mesh inbox**

After the STOP detection block (after the `fi` that closes the stop-flag clearing logic, before the mesh inbox section), add:

```bash
# --- Skill intent classification (Tier 1: deterministic) ---
source "$SCRIPT_DIR/lib/skill-router.sh"
USER_TEXT=$(echo "$INPUT" | jq -r '
  if (.content | type) == "array" then
    [.content[] | select(.type == "text") | .text] | join(" ")
  else
    .content // ""
  end' 2>/dev/null || true)

MATCHED_SKILL=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_SKILL" ]; then
  SKILL_HINT=$(format_skill_hint "$MATCHED_SKILL")
  echo "$SKILL_HINT"
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/inject-prompt-context.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/inject-prompt-context.sh
git commit -m "feat: wire skill-router into UserPromptSubmit hook

Classifies user intent at Tier 1 (keywords) and injects a skill hint
into context when a matching skill is found. Zero-token, sub-ms."
```

---

### Task 3: Create memory-combined.sh — merged extraction + reflection

**Files:**
- Create: `plugin/scripts/memory-combined.sh`

- [ ] **Step 1: Create the combined memory hook**

```bash
#!/bin/bash
# memory-combined.sh — Async Stop hook: deterministic extraction + conditional AI reflection
# Replaces both memory-extract-fast.sh and memory-reflect.sh.
# Phase 1 (deterministic) always runs and saves candidates.
# Phase 2 (AI reflection) only runs if high-signal candidates found AND session is substantial.
set -euo pipefail

[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

source "$SCRIPT_DIR/lib/worktree.sh"
source "$SCRIPT_DIR/lib/portable-lock.sh"
source "$SCRIPT_DIR/lib/telemetry.sh"

SESSION_ID=$(hook_get_field '.session_id' 2>/dev/null || true)
TRANSCRIPT=$(hook_get_field '.transcript_path' 2>/dev/null || true)
CWD=$(hook_get_field '.cwd' 2>/dev/null || echo ".")

# Skip if no transcript
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# ════════════════════════════════════════════════════════════
# PHASE 1: Deterministic extraction (always runs, never lost)
# ════════════════════════════════════════════════════════════

CANDIDATES_FILE="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/data/memory-candidates.jsonl"
mkdir -p "$(dirname "$CANDIDATES_FILE")"

TAIL_CONTENT=$(tail -100 "$TRANSCRIPT" 2>/dev/null || true)
[ -z "$TAIL_CONTENT" ] && exit 0

HIGH_SIGNAL=0

# Extract user corrections
CORRECTIONS=$(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "human" or .role == "user") |
  .content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end' 2>/dev/null |
  grep -iE "don.t|instead|wrong|shouldn.t|stop doing|not that|no,|actually|prefer|always|never" || true)

if [ -n "$CORRECTIONS" ]; then
  HIGH_SIGNAL=1
  portable_lock "$CANDIDATES_FILE.lock" 2>/dev/null || true
  printf '{"session_id":"%s","type":"correction","content":"%s","ts":"%s"}\n' \
    "$SESSION_ID" "$(echo "$CORRECTIONS" | head -3 | tr '\n"' '  ')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >> "$CANDIDATES_FILE" 2>/dev/null || true
  portable_unlock "$CANDIDATES_FILE.lock" 2>/dev/null || true
fi

# Extract error patterns
ERRORS=$(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") | .content |
  if type == "array" then map(select(.type == "tool_result") | .content) | join(" ") else . end' 2>/dev/null |
  grep -iE "error|exception|failed|traceback|panic" | head -5 || true)

if [ -n "$ERRORS" ]; then
  HIGH_SIGNAL=1
  portable_lock "$CANDIDATES_FILE.lock" 2>/dev/null || true
  printf '{"session_id":"%s","type":"error","content":"%s","ts":"%s"}\n' \
    "$SESSION_ID" "$(echo "$ERRORS" | head -3 | tr '\n"' '  ')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >> "$CANDIDATES_FILE" 2>/dev/null || true
  portable_unlock "$CANDIDATES_FILE.lock" 2>/dev/null || true
fi

# Extract file churn
EDIT_COUNTS=$(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") | .content |
  if type == "array" then .[] | select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) | .input.file_path else empty end' 2>/dev/null |
  sort | uniq -c | sort -rn || true)

while IFS= read -r line; do
  [ -z "$line" ] && continue
  count=$(echo "$line" | awk '{print $1}')
  file=$(echo "$line" | awk '{print $2}')
  if [ "${count:-0}" -ge 3 ]; then
    HIGH_SIGNAL=1
    portable_lock "$CANDIDATES_FILE.lock" 2>/dev/null || true
    printf '{"session_id":"%s","type":"churn","file":"%s","count":%s,"ts":"%s"}\n' \
      "$SESSION_ID" "$file" "$count" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      >> "$CANDIDATES_FILE" 2>/dev/null || true
    portable_unlock "$CANDIDATES_FILE.lock" 2>/dev/null || true
  fi
done <<< "$EDIT_COUNTS"

hook_log "memory-combined: phase 1 complete (high_signal=$HIGH_SIGNAL)"

# ════════════════════════════════════════════════════════════
# PHASE 2: AI reflection (conditional, graceful degradation)
# ════════════════════════════════════════════════════════════

# Only run if: high-signal candidates found AND claude CLI available AND session > 5 min
if [ "$HIGH_SIGNAL" -eq 0 ]; then
  hook_log "memory-combined: skipping phase 2 (no high-signal candidates)"
  exit 0
fi

command -v claude &>/dev/null || { hook_log "memory-combined: skipping phase 2 (no claude CLI)"; exit 0; }

# Session age check
REPO_ROOT=$(get_repo_root 2>/dev/null || echo "$CWD")
MEMORY_DIR="$HOME/.claude/projects/$(echo "$REPO_ROOT" | md5sum | cut -d' ' -f1)/memory"
START_MARKER="$MEMORY_DIR/.session-start-${SESSION_ID}"
if [ -f "$START_MARKER" ]; then
  START_AGE=$(( $(date +%s) - $(stat -c %Y "$START_MARKER" 2>/dev/null || echo "$(date +%s)") ))
  if [ "$START_AGE" -lt 300 ]; then
    hook_log "memory-combined: skipping phase 2 (session < 5 min)"
    exit 0
  fi
fi

mkdir -p "$MEMORY_DIR"

# Extract user messages for AI prompt
USER_MSGS=$(jq -r '
  select(.role == "human" or .role == "user") |
  .content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end' \
  "$TRANSCRIPT" 2>/dev/null | head -50 || true)

FILTERED_MSGS=""
while IFS= read -r msg; do
  [ ${#msg} -lt 15 ] && continue
  echo "$msg" | grep -qiE '^(ok|yes|done|continue|thanks|go ahead|lgtm|y|sure|perfect)$' && continue
  FILTERED_MSGS="${FILTERED_MSGS}${msg}\n"
done <<< "$USER_MSGS"

LINE_COUNT=$(printf '%b' "$FILTERED_MSGS" | wc -l)
[ "$LINE_COUNT" -lt 3 ] && { hook_log "memory-combined: skipping phase 2 (< 3 meaningful messages)"; exit 0; }

EXISTING_MEMORIES=""
[ -f "$MEMORY_DIR/MEMORY.md" ] && EXISTING_MEMORIES=$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true)

REFLECT_PROMPT="You are a memory extraction agent. Extract 1-3 high-confidence learnings from this session.

Rules:
- Each memory MUST be grounded in a direct quote from the user
- Types: feedback (user correction), project (work context), reference (external pointer), user (about the person)
- Format each as: FILE:filename.md | NAME:short name | DESC:one line | TYPE:type | BODY:content | END
- Skip if nothing is genuinely worth remembering
- Max 3 memories

Existing memories (do not duplicate):
${EXISTING_MEMORIES}

User messages from this session:
$(printf '%b' "$FILTERED_MSGS")"

AI_RESULT=$(printf '%b' "$FILTERED_MSGS" | timeout 45 claude -p "$REFLECT_PROMPT" --no-input --model sonnet 2>/dev/null || echo "")

if [ -z "$AI_RESULT" ]; then
  hook_log "memory-combined: phase 2 AI unavailable or empty"
  exit 0
fi

# Parse and write memories
CURRENT_FILE="" CURRENT_NAME="" CURRENT_DESC="" CURRENT_TYPE="" CURRENT_BODY=""
while IFS= read -r line; do
  case "$line" in
    FILE:*) CURRENT_FILE="${line#FILE:}" ; CURRENT_FILE=$(echo "$CURRENT_FILE" | xargs) ;;
    NAME:*) CURRENT_NAME="${line#NAME:}" ; CURRENT_NAME=$(echo "$CURRENT_NAME" | xargs) ;;
    DESC:*) CURRENT_DESC="${line#DESC:}" ; CURRENT_DESC=$(echo "$CURRENT_DESC" | xargs) ;;
    TYPE:*) CURRENT_TYPE="${line#TYPE:}" ; CURRENT_TYPE=$(echo "$CURRENT_TYPE" | xargs) ;;
    BODY:*) CURRENT_BODY="${line#BODY:}" ;;
    END)
      if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_BODY" ] && [ ! -f "$MEMORY_DIR/$CURRENT_FILE" ]; then
        cat > "$MEMORY_DIR/$CURRENT_FILE" <<MEMEOF
---
name: ${CURRENT_NAME}
description: ${CURRENT_DESC}
type: ${CURRENT_TYPE}
---

${CURRENT_BODY}
MEMEOF
        # Update MEMORY.md index
        if [ -f "$MEMORY_DIR/MEMORY.md" ] && ! grep -qF "$CURRENT_FILE" "$MEMORY_DIR/MEMORY.md" 2>/dev/null; then
          echo "- [${CURRENT_NAME}](${CURRENT_FILE}) — ${CURRENT_DESC}" >> "$MEMORY_DIR/MEMORY.md"
        fi
        hook_log "memory-combined: wrote $CURRENT_FILE"
      fi
      CURRENT_FILE="" CURRENT_NAME="" CURRENT_DESC="" CURRENT_TYPE="" CURRENT_BODY=""
      ;;
    *) [ -n "$CURRENT_BODY" ] && CURRENT_BODY="${CURRENT_BODY}\n${line}" ;;
  esac
done <<< "$AI_RESULT"

hook_log "memory-combined: phase 2 complete"
exit 0
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n plugin/scripts/memory-combined.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/memory-combined.sh
git commit -m "feat: create memory-combined.sh (merged extract + reflect)

Single async Stop hook replaces both memory-extract-fast.sh and
memory-reflect.sh. Phase 1 (deterministic) always saves candidates.
Phase 2 (AI) only runs if high-signal candidates found."
```

---

### Task 4: Update hooks.json and delete old memory hooks

**Files:**
- Modify: `plugin/hooks/hooks.json` (Stop section)
- Delete: `plugin/scripts/memory-extract-fast.sh`
- Delete: `plugin/scripts/memory-reflect.sh`

- [ ] **Step 1: Update hooks.json Stop section**

Replace the two separate memory hook entries:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/memory-extract-fast.sh",
            "async": true,
            "timeout": 10
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/memory-reflect.sh",
            "async": true,
            "timeout": 60
          }
        ]
      },
```

With a single combined entry:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/memory-combined.sh",
            "async": true,
            "timeout": 60
          }
        ]
      },
```

- [ ] **Step 2: Delete old memory hooks**

```bash
rm plugin/scripts/memory-extract-fast.sh plugin/scripts/memory-reflect.sh
```

- [ ] **Step 3: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('plugin/hooks/hooks.json'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/hooks/hooks.json
git rm plugin/scripts/memory-extract-fast.sh plugin/scripts/memory-reflect.sh
git commit -m "feat: replace 2 memory hooks with 1 combined hook

memory-extract-fast.sh + memory-reflect.sh merged into memory-combined.sh.
Deterministic extraction always saves candidates (never lost to timeout).
AI reflection only runs when high-signal candidates found."
```

---

## Self-Review

1. **Spec coverage:** ✓ Intent classification at UserPromptSubmit, ✓ HARD GATE via skill hint injection, ✓ Memory hooks merged 3→2 (really 2→1 since FTS index is a separate concern)
2. **Placeholder scan:** No TBD/TODO/placeholder found. All code blocks complete.
3. **Type consistency:** `classify_intent()` and `format_skill_hint()` used consistently. `HIGH_SIGNAL` flag used consistently in memory-combined.sh.
