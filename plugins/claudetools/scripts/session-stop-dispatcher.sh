#!/bin/bash
# Stop dispatcher — runs task-quality validator and session-stop-gate quality check
set -euo pipefail

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/task-quality.sh"

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
  record_hook_outcome "$name" "Stop" "$decision" "" "" ""
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "session-stop-dispatcher" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}

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
  record_hook_outcome "$name" "Stop" "$decision" "" "" ""
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "session-stop-dispatcher" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}

run_validator "task-quality"  validate_task_quality
run_script_validator "stop-gate" "$SCRIPT_DIR/session-stop-gate.sh"

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="$( [ "$MAX_EXIT" -ge 2 ] && echo block || echo warn )"
  HOOK_REASON="stop blocked by quality gate"
fi

record_hook_outcome "session-stop-dispatcher" "Stop" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "" "" ""
exit $MAX_EXIT
