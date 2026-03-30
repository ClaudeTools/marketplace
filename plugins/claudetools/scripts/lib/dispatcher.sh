#!/bin/bash
# Shared dispatcher library — run_validator, run_script_validator, run_async_validator
#
# Must be sourced after setting these globals:
#   DISPATCHER_EVENT        — event type passed to record_hook_outcome (e.g. "PostToolUse")
#   DISPATCHER_TOOL         — tool name passed to record_hook_outcome (e.g. "Bash", or "")
#   DISPATCHER_NAME         — dispatcher name passed to emit_validator_event (e.g. "post-bash-gate")
#   DISPATCHER_MODEL_FAMILY — model family for record_hook_outcome (set to "$MODEL_FAMILY" or "")
#
# Requires record_hook_outcome and emit_validator_event (sourced via lib/telemetry.sh or lib/thresholds.sh).
# Operates on globals ALL_FINDINGS and MAX_EXIT (must be initialised by caller).

# run_validator NAME FUNC
# Runs FUNC, captures output+exit, aggregates findings, records outcome, emits telemetry.
# Modifies ALL_FINDINGS and MAX_EXIT. Always returns 0.
run_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$("$func" 2>&1) || rc=$?
  local decision="allow"
  [ "$rc" -ge 2 ] && decision="block"
  [ "$rc" -eq 1 ] && decision="warn"
  if [ "$rc" -gt 0 ] && [ -n "$output" ]; then
    ALL_FINDINGS="${ALL_FINDINGS}${output}\n"
    [ "$rc" -gt "$MAX_EXIT" ] && MAX_EXIT=$rc
  fi
  record_hook_outcome "$name" "$DISPATCHER_EVENT" "$decision" "$DISPATCHER_TOOL" "" "" "$DISPATCHER_MODEL_FAMILY"
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "$DISPATCHER_NAME" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}

# run_script_validator NAME SCRIPT
# Like run_validator but runs an external script as a subprocess, piping $INPUT to it.
# Modifies ALL_FINDINGS and MAX_EXIT. Always returns 0.
run_script_validator() {
  local name="$1"
  local script="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$(echo "$INPUT" | bash "$script" 2>&1) || rc=$?
  local decision="allow"
  if [ "$rc" -ge 2 ]; then
    decision="block"
  elif [ "$rc" -eq 1 ]; then
    decision="warn"
  fi
  if [ "$rc" -gt 0 ] && [ -n "$output" ]; then
    ALL_FINDINGS="${ALL_FINDINGS}${output}\n"
    [ "$rc" -gt "$MAX_EXIT" ] && MAX_EXIT=$rc
  fi
  record_hook_outcome "$name" "$DISPATCHER_EVENT" "$decision" "$DISPATCHER_TOOL" "" "" "$DISPATCHER_MODEL_FAMILY"
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "$DISPATCHER_NAME" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}

# run_async_validator NAME FUNC
# Runs FUNC but never blocks — always returns 0. Logs failures via hook_log. Emits telemetry.
# Does NOT modify ALL_FINDINGS or MAX_EXIT.
run_async_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$("$func" 2>&1) || rc=$?
  local decision="allow"
  [ "$rc" -ge 2 ] && decision="block"
  [ "$rc" -eq 1 ] && decision="warn"
  if [ "$rc" -ne 0 ]; then
    hook_log "${DISPATCHER_NAME}: $name failed (rc=$rc): $output"
  fi
  record_hook_outcome "$name" "$DISPATCHER_EVENT" "$decision" "$DISPATCHER_TOOL" "" "" "$DISPATCHER_MODEL_FAMILY"
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "$DISPATCHER_NAME" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}
