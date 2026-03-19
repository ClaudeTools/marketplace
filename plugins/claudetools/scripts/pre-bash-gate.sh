#!/bin/bash
# PreToolUse:Bash dispatcher
# Replaces: block-dangerous-bash.sh, ai-safety.sh, block-unasked-restructure.sh
# Safety-critical — stops on FIRST block, does not continue to further validators.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/dangerous-bash.sh"
source "$SCRIPT_DIR/validators/ai-safety.sh"
source "$SCRIPT_DIR/validators/unasked-restructure.sh"

# Phase 3: Run validators — stop on FIRST block (safety-critical)
# PreToolUse protocol: block via JSON stdout, warnings as systemMessage, exit 0
run_pretool_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$("$func" 2>&1) || rc=$?

  if [ "$rc" -eq 2 ]; then
    # Hard block — emit JSON to stdout and exit immediately (safety-critical: no further checks)
    jq -n --arg reason "$output" \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
    HOOK_DECISION="block"
    HOOK_REASON="$output"
    record_hook_outcome "$name" "PreToolUse" "block" "Bash" "" "" "$MODEL_FAMILY"
    record_hook_outcome "pre-bash-gate" "PreToolUse" "block" "Bash" "" "" "$MODEL_FAMILY"
    local _t_end _duration_ms
    _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
    _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
    emit_event "$name" "validator_run" "warn" "$_duration_ms" '{"dispatcher":"pre-bash-gate"}' 2>/dev/null || true
    exit 0
  elif [ "$rc" -eq 1 ] && [ -n "$output" ]; then
    # Warning — emit as systemMessage
    echo "{\"systemMessage\":$(echo "$output" | jq -Rs .)}"
    record_hook_outcome "$name" "PreToolUse" "warn" "Bash" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "PreToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_event "$name" "validator_run" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" '{"dispatcher":"pre-bash-gate"}' 2>/dev/null || true
}

run_pretool_validator "block-dangerous-bash"      validate_dangerous_bash
run_pretool_validator "ai-safety"                 validate_ai_safety
run_pretool_validator "block-unasked-restructure" validate_unasked_restructure

record_hook_outcome "pre-bash-gate" "PreToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
exit 0
