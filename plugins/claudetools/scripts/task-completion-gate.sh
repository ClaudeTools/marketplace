#!/bin/bash
# TaskCompleted dispatcher
# Replaces: task-quality.sh, task-done.sh, git-commits.sh, ran-checks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/task-quality.sh"
source "$SCRIPT_DIR/validators/task-done.sh"
source "$SCRIPT_DIR/validators/git-commits.sh"
source "$SCRIPT_DIR/validators/ran-checks.sh"
source "$SCRIPT_DIR/validators/no-deferred-actions.sh"

# Phase 3: Run validators, aggregate results
# TaskCompleted protocol: findings on stderr, exit MAX_EXIT (block on 2)
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
    record_hook_outcome "$name" "TaskCompleted" "warn" "" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "TaskCompleted" "allow" "" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "task-completion-gate" "$name" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" "$output" 2>/dev/null || true
}

run_validator "task-quality" validate_task_quality
run_validator "task-done"    validate_task_done
run_validator "git-commits"  validate_git_commits
run_validator "ran-checks"   validate_ran_checks
run_validator "no-deferred-actions" validate_no_deferred_actions

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="$( [ "$MAX_EXIT" -ge 2 ] && echo block || echo warn )"
  HOOK_REASON="task completion blocked by quality gate"
fi

record_hook_outcome "task-completion-gate" "TaskCompleted" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
