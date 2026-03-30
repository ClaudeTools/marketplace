#!/bin/bash
# ai-session-audit.sh — Async Stop hook: AI-powered session quality audit
# Extracted from session-stop-gate.sh Tier 3 to run asynchronously.
# Produces warnings only (never blocks). Findings logged to session log.
set -euo pipefail

[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

source "$SCRIPT_DIR/lib/thresholds.sh"
MODEL_FAMILY=$(detect_model_family)

CWD=$(hook_get_field '.cwd' 2>/dev/null || echo ".")

# Only run in git repos
if ! git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

# Get diff from last commit
DIFF=$(git -C "$CWD" diff HEAD~1 HEAD 2>/dev/null || true)
DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

# Threshold check — skip small diffs
AI_AUDIT_LIMIT=$(get_threshold "ai_audit_diff_threshold" 2>/dev/null || echo "500")
AI_AUDIT_LIMIT=${AI_AUDIT_LIMIT%.*}
if [ "$DIFF_LINES" -le "$AI_AUDIT_LIMIT" ]; then
  exit 0
fi

# claude CLI required
if ! command -v claude &>/dev/null; then
  exit 0
fi

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

hook_log "AI audit: invoking on ${DIFF_LINES}-line diff (async)"

AI_RESULT=$(echo "$DIFF" | timeout 30 claude -p "$AI_PROMPT" --no-input --model haiku 2>/dev/null || echo "AI_UNAVAILABLE")

if [ "$AI_RESULT" = "AI_UNAVAILABLE" ]; then
  hook_log "AI audit: unavailable (timeout or CLI not found)"
elif echo "$AI_RESULT" | grep -qi "^CLEAN$"; then
  hook_log "AI audit: CLEAN"
else
  hook_log "AI audit: findings reported"
  # Log findings — async hooks can't inject into conversation, but we log for telemetry
  echo "$AI_RESULT" >> "$(hook_get_field '.cwd' 2>/dev/null || echo /tmp)/ai-session-audit.log" 2>/dev/null || true
fi

record_hook_outcome "ai-session-audit" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
