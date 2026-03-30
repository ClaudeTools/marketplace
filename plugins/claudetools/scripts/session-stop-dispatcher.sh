#!/bin/bash
# Stop dispatcher — runs task-quality validator and session-stop-gate quality check
set -euo pipefail

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Diagnostic: log Stop event context for worktree session debugging
echo "STOP-DIAG: $(date -u +%Y-%m-%dT%H:%M:%SZ) CWD=$(pwd) SESSION_ID=${SESSION_ID:-unknown} WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || echo none)" >> /tmp/claudetools-stop-diagnostic.log

# Phase 2: Source validators
source "$SCRIPT_DIR/lib/hook-skip.sh"
source "$SCRIPT_DIR/lib/git-state.sh"
source "$SCRIPT_DIR/validators/task-quality.sh"
source "$SCRIPT_DIR/validators/session-stop-gate.sh"

# Phase 3: Run validators, aggregate results
# Stop protocol: findings on stderr, exit MAX_EXIT (block on 2)
MAX_EXIT=0
ALL_FINDINGS=""

DISPATCHER_EVENT="Stop"
DISPATCHER_TOOL=""
DISPATCHER_NAME="session-stop-dispatcher"
DISPATCHER_MODEL_FAMILY=""
source "$SCRIPT_DIR/lib/dispatcher.sh"

run_validator "task-quality"  validate_task_quality
run_validator "stop-gate"    validate_session_stop_gate

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="$( [ "$MAX_EXIT" -ge 2 ] && echo block || echo warn )"
  HOOK_REASON="stop blocked by quality gate"
fi

record_hook_outcome "session-stop-dispatcher" "Stop" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "" "" ""
exit $MAX_EXIT
