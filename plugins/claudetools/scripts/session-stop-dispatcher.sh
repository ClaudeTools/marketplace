#!/bin/bash
# Stop dispatcher (sync)
# Replaces: session-stop-gate.sh (task-quality.sh + stop-gate.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/task-quality.sh"
source "$SCRIPT_DIR/validators/stop-gate.sh"

# Phase 3: Run validators, aggregate results
# Stop protocol: findings on stderr, exit MAX_EXIT (block on 2)
MAX_EXIT=0
ALL_FINDINGS=""

run_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$("$func" 2>&1) || rc=$?
  if [ "$rc" -gt 0 ] && [ -n "$output" ]; then
    ALL_FINDINGS="${ALL_FINDINGS}${output}\n"
    [ "$rc" -gt "$MAX_EXIT" ] && MAX_EXIT=$rc
    record_hook_outcome "$name" "Stop" "warn" "" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "session-stop-dispatcher" "$name" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" "$output" 2>/dev/null || true
}

run_validator "task-quality" validate_task_quality
run_validator "stop-gate"    validate_stop_gate

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="$( [ "$MAX_EXIT" -ge 2 ] && echo block || echo warn )"
  HOOK_REASON="stop blocked by quality gate"
fi

record_hook_outcome "session-stop-dispatcher" "Stop" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
