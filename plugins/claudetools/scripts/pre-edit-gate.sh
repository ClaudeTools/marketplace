#!/bin/bash
# PreToolUse:Edit|Write dispatcher
# Replaces: require-active-task.sh, enforce-task-scope.sh, research-backing-gate.sh, detect-bulk-edit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/active-task.sh"
source "$SCRIPT_DIR/validators/blind-edit.sh"
source "$SCRIPT_DIR/validators/task-scope.sh"
source "$SCRIPT_DIR/validators/research-backing.sh"
source "$SCRIPT_DIR/validators/bulk-edit.sh"
source "$SCRIPT_DIR/validators/prefer-edit-over-write.sh"
source "$SCRIPT_DIR/validators/mesh-lock.sh"

# Phase 3: Run validators in order — stop on first block
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
    # Hard block — emit JSON to stdout and exit
    jq -n --arg reason "$output" \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
    HOOK_DECISION="block"
    HOOK_REASON="$output"
    record_hook_outcome "$name" "PreToolUse" "block" "" "" "" "$MODEL_FAMILY"
    local _t_end _duration_ms
    _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
    _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
    emit_validator_event "pre-edit-gate" "$name" "block" "$_duration_ms" "$output" 2>/dev/null || true
    exit 0
  elif [ "$rc" -eq 1 ] && [ -n "$output" ]; then
    # Warning — emit as systemMessage
    echo "{\"systemMessage\":$(echo "$output" | jq -Rs .)}"
    record_hook_outcome "$name" "PreToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "pre-edit-gate" "$name" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" "$output" 2>/dev/null || true
}

run_pretool_validator "blind-edit-guard"         validate_blind_edit
run_pretool_validator "require-active-task"      validate_active_task
run_pretool_validator "enforce-task-scope"       validate_task_scope
run_pretool_validator "research-backing-gate"    validate_research_backing
run_pretool_validator "detect-bulk-edit"         validate_bulk_edit
run_pretool_validator "prefer-edit-over-write"   validate_prefer_edit_over_write
run_pretool_validator "mesh-lock-check"         validate_mesh_lock

record_hook_outcome "pre-edit-gate" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
