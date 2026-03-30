#!/bin/bash
# TaskCompleted dispatcher — task-quality, task-done, git-commits, ran-checks
set -euo pipefail

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/lib/hook-skip.sh"
source "$SCRIPT_DIR/validators/task-quality.sh"
source "$SCRIPT_DIR/validators/task-done.sh"
source "$SCRIPT_DIR/validators/git-commits.sh"
source "$SCRIPT_DIR/validators/ran-checks.sh"
source "$SCRIPT_DIR/validators/no-deferred-actions.sh"

# Phase 3: Run validators, aggregate results
# TaskCompleted protocol: findings on stderr, exit MAX_EXIT (block on 2)
MAX_EXIT=0
ALL_FINDINGS=""

DISPATCHER_EVENT="TaskCompleted"
DISPATCHER_TOOL=""
DISPATCHER_NAME="task-completion-gate"
DISPATCHER_MODEL_FAMILY="$MODEL_FAMILY"
source "$SCRIPT_DIR/lib/dispatcher.sh"

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
