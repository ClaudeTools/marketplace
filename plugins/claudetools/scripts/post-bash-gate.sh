#!/bin/bash
# PostToolUse:Bash dispatcher — runs unasked-deps and deploy-loop-detector validators
set -euo pipefail

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/unasked-deps.sh"
source "$SCRIPT_DIR/validators/deploy-loop-detector.sh"

# Phase 3: Run validators, aggregate results
# PostToolUse protocol: findings on stderr, exit MAX_EXIT
MAX_EXIT=0
ALL_FINDINGS=""

DISPATCHER_EVENT="PostToolUse"
DISPATCHER_TOOL="Bash"
DISPATCHER_NAME="post-bash-gate"
DISPATCHER_MODEL_FAMILY="$MODEL_FAMILY"
source "$SCRIPT_DIR/lib/dispatcher.sh"

run_validator "detect-unasked-deps"        validate_unasked_deps
run_validator "deploy-loop-detector"      validate_deploy_loop

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="warn"
  HOOK_REASON="post-bash issues detected"
fi

record_hook_outcome "post-bash-gate" "PostToolUse" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "Bash" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
