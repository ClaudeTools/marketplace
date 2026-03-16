#!/usr/bin/env bash
# Stop event hook — comprehensive multi-tier quality gate
# Fires when an agent or session stops. Combines deterministic, semantic,
# and AI inference checks to ensure no incomplete or broken work is left behind.
#
# Tier 1: Deterministic (exit 2 = hard block)
#   - Uncommitted changes, main branch, stub patterns, sensitive files
# Tier 2: Semantic grep-based (exit 1 = warning)
#   - Weasel phrases, scope creep, in-progress tasks
# Tier 3: AI inference (exit 1 = warning, graceful degradation)
#   - Haiku review of changed files for completeness/stubs
#
# Exit codes:
#   0 = all clear
#   1 = Tier 2/3 warnings (non-blocking, injected into conversation)
#   2 = Tier 1 failure (hard block, stderr fed back as instructions)

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
METRICS_DB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/data/metrics.db"
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)

# Prevent infinite loops — if this is a re-evaluation after blocking, allow stop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null || true)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  hook_log "stop_hook_active=true, allowing stop"
  exit 0
fi
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# Track results for summary
TIER1_PASS=()
TIER1_FAIL=()
TIER2_WARNINGS=()
TIER3_RESULT=""

summary() {
  # Only print failures and warnings — skip passes and decoration
  local HAS_OUTPUT=0

  for f in "${TIER1_FAIL[@]}"; do
    echo "$f" >&2
    HAS_OUTPUT=1
  done

  for w in "${TIER2_WARNINGS[@]}"; do
    echo "$w" >&2
    HAS_OUTPUT=1
  done

  if [ -n "$TIER3_RESULT" ] && ! echo "$TIER3_RESULT" | grep -q "PASS\|SKIPPED"; then
    echo "$TIER3_RESULT" >&2
    HAS_OUTPUT=1
  fi
}

# ═══════════════════════════════════════════════════════════════
# TIER 1: Deterministic checks (exit 2 on failure)
# ═══════════════════════════════════════════════════════════════

IS_GIT=0
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
fi

# --- 1a. Main branch check ---
if [ "$IS_GIT" -eq 1 ]; then
  CURRENT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    TIER1_FAIL+=("[BRANCH] On $CURRENT_BRANCH — create a feature branch first")
    HOOK_DECISION="reject"; HOOK_REASON="on main branch"
    summary
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
    exit 2
  else
    TIER1_PASS+=("Branch: $CURRENT_BRANCH (not main/master)")
  fi
fi

# --- 1b. Uncommitted changes ---
CHANGED_FILES=""
if [ "$IS_GIT" -eq 1 ]; then
  STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || true)
  UNSTAGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
  UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
  ALL_CHANGED=$(printf '%s\n%s\n%s' "$STAGED" "$UNSTAGED" "$UNTRACKED" | sort -u | sed '/^$/d')
  # Filter out system/artifact files that aren't real code changes
  CHANGED_FILES=$(echo "$ALL_CHANGED" | grep -vE '^\.(claude|DS_Store)|\.lock$|\.tsbuildinfo$|^node_modules/|^\.git/' | sed '/^$/d' || true)

  if [ -n "$CHANGED_FILES" ]; then
    FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
    TIER1_FAIL+=("[UNCOMMITTED] $FILE_COUNT uncommitted file(s) — commit or stash before stopping")
    HOOK_DECISION="reject"; HOOK_REASON="uncommitted changes"
    summary
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
    exit 2
  else
    TIER1_PASS+=("No uncommitted changes")
  fi
fi

# If no git repo or no changes, skip remaining file-level checks
if [ -z "$CHANGED_FILES" ] && [ "$IS_GIT" -eq 0 ]; then
  TIER1_PASS+=("Not a git repo — skipping file checks")
  summary
  record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
  exit 0
fi

# --- 1c. Sensitive files staged ---
if [ "$IS_GIT" -eq 1 ]; then
  SENSITIVE_STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null | grep -iE '\.(env|key|pem|p12|pfx|keystore)$|credentials|secrets' || true)
  if [ -n "$SENSITIVE_STAGED" ]; then
    TIER1_FAIL+=("Sensitive files staged: $(echo "$SENSITIVE_STAGED" | tr '\n' ', ')")
    TIER1_FAIL+=("[SENSITIVE] Sensitive files staged — unstage before committing")
    HOOK_DECISION="reject"; HOOK_REASON="sensitive files staged"
    summary
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
    exit 2
  else
    TIER1_PASS+=("No sensitive files staged")
  fi
fi

# --- 1d. Stub/TODO/FIXME patterns in recently changed files ---
# Check committed files from recent work (last commit vs HEAD~1)
RECENT_CODE_FILES=""
if [ "$IS_GIT" -eq 1 ]; then
  RECENT_CODE_FILES=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|py|go|rs|rb|java)$' | grep -vE '\.test\.|\.spec\.|__tests__|__mocks__' || true)
fi

STUB_VIOLATIONS=""
STUB_COUNT=0
if [ -n "$RECENT_CODE_FILES" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    FULL_PATH="$file"
    [ "${file:0:1}" != "/" ] && FULL_PATH="$CWD/$file"
    [ -f "$FULL_PATH" ] || continue

    COUNT=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme|placeholder)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|HACK:' "$FULL_PATH" 2>/dev/null || true)
    COUNT=${COUNT:-0}
    if [ "$COUNT" -gt 0 ]; then
      STUB_VIOLATIONS="${STUB_VIOLATIONS}\n  $(basename "$file"): ${COUNT} stub/TODO markers"
      STUB_COUNT=$((STUB_COUNT + COUNT))
    fi
  done <<< "$RECENT_CODE_FILES"
fi

if [ "$STUB_COUNT" -gt 0 ]; then
  TIER1_FAIL+=("[STUBS] $STUB_COUNT stub/TODO patterns in recent changes — implement or remove them")
  HOOK_DECISION="reject"; HOOK_REASON="stubs in changed files"
  summary
  printf '%b\n' "$STUB_VIOLATIONS" >&2
  record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
  exit 2
else
  TIER1_PASS+=("No stub/TODO patterns in recent changes")
fi

# ═══════════════════════════════════════════════════════════════
# TIER 2: Semantic checks (grep-based, exit 1 = warning)
# ═══════════════════════════════════════════════════════════════

# --- 2a. Weasel phrases in recent agent transcript ---
# The INPUT may contain transcript or tool output from the session
WEASEL_HITS=$(echo "$INPUT" | grep -oiE 'should work|looks correct|appears to|I believe this fixes|it should be fine|probably works|seems to work|I think this is right|this might fix|likely resolves' 2>/dev/null || true)
if [ -n "$WEASEL_HITS" ]; then
  WEASEL_COUNT=$(echo "$WEASEL_HITS" | wc -l | tr -d ' ')
  TIER2_WARNINGS+=("$WEASEL_COUNT weasel phrase(s) detected — verify claims with tests, not confidence")
fi

# --- 2b. Scope check on recent commit ---
if [ "$IS_GIT" -eq 1 ]; then
  RECENT_CHANGED=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ' || true)
  RECENT_CHANGED=${RECENT_CHANGED:-0}
  [[ "$RECENT_CHANGED" =~ ^[0-9]+$ ]] || RECENT_CHANGED=0
  LARGE_CHANGE=$(get_threshold "large_change_threshold" "$MODEL_FAMILY")
  LARGE_CHANGE=${LARGE_CHANGE%.*}
  if [ "$RECENT_CHANGED" -gt "$LARGE_CHANGE" ]; then
    TIER2_WARNINGS+=("Large change set: $RECENT_CHANGED files in last commit — verify scope matches the task")
  fi
fi

# --- 2c. (Removed: project-specific task file checks) ---

# ═══════════════════════════════════════════════════════════════
# TIER 3: AI inference (optional, graceful degradation)
# ═══════════════════════════════════════════════════════════════

# Only run AI tier if there are recent code changes to review
if [ "$IS_GIT" -eq 1 ]; then
  DIFF=$(git -C "$CWD" diff HEAD~1 HEAD 2>/dev/null || true)
  DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

  AI_AUDIT_LIMIT=$(get_threshold "ai_audit_diff_threshold" "$MODEL_FAMILY")
  AI_AUDIT_LIMIT=${AI_AUDIT_LIMIT%.*}
  if [ "$DIFF_LINES" -gt "$AI_AUDIT_LIMIT" ]; then
    RECENT_FILE_LIST=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | head -20 || true)

    AI_PROMPT="You are a session-end quality auditor. An agent is about to stop working. Review the diff from the last commit for completeness and quality issues.

Focus ONLY on:
1. INCOMPLETE WORK: Functions that are declared but have stub/placeholder bodies. Endpoints with no real logic.
2. CLAIMED-BUT-NOT-DONE: Comments saying 'implemented X' but the code doesn't actually do X.
3. MISSING ERROR HANDLING: New API endpoints or async operations with no error handling at all.
4. HARDCODED VALUES: Values that should clearly be configurable or come from config/env but are inline constants.

Changed files:
${RECENT_FILE_LIST}

Respond with ONLY a bulleted list of findings, or 'CLEAN' if no issues found.
Keep response under 8 lines. No preamble. No praise."

    hook_log "Tier 3: invoking AI audit on ${DIFF_LINES}-line diff"

    AI_RESULT=$(echo "$DIFF" | timeout 30 claude -p "$AI_PROMPT" --no-input --model haiku 2>/dev/null || echo "AI_UNAVAILABLE")

    if [ "$AI_RESULT" = "AI_UNAVAILABLE" ]; then
      TIER3_RESULT="[SKIPPED] AI audit unavailable (timeout or CLI not found)"
      hook_log "Tier 3: AI unavailable — skipped"
    elif echo "$AI_RESULT" | grep -qi "^CLEAN$"; then
      TIER3_RESULT="[PASS] AI audit found no issues"
      hook_log "Tier 3: CLEAN"
    else
      TIER3_RESULT="[FINDINGS] AI audit flagged issues"
      TIER2_WARNINGS+=("AI audit findings (non-blocking):")
      while IFS= read -r line; do
        [ -n "$line" ] && TIER2_WARNINGS+=("  $line")
      done <<< "$AI_RESULT"
      hook_log "Tier 3: findings reported"
    fi
  else
    TIER3_RESULT="[SKIPPED] Diff too small ($DIFF_LINES lines) — not worth AI audit"
  fi
else
  TIER3_RESULT="[SKIPPED] Not a git repo"
fi

# ═══════════════════════════════════════════════════════════════
# FINAL DECISION
# ═══════════════════════════════════════════════════════════════

# Tier 1 all passed (otherwise we'd have exited already)
# Check if Tier 2/3 produced warnings
if [ ${#TIER2_WARNINGS[@]} -gt 0 ]; then
  HOOK_DECISION="warn"; HOOK_REASON="tier 2/3 warnings"
  summary
  record_hook_outcome "session-stop-gate" "Stop" "warn" "" "large_change_threshold" "${LARGE_CHANGE:-}" "$MODEL_FAMILY"
  exit 1
fi

# All clear
HOOK_DECISION="allow"; HOOK_REASON="all tiers passed"
summary
record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
