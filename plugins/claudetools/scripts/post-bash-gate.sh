#!/bin/bash
# PostToolUse:Bash dispatcher
# Replaces: enforce-deploy-then-verify.sh, detect-unasked-deps.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/deploy-then-verify.sh"
source "$SCRIPT_DIR/validators/unasked-deps.sh"

# Phase 3: Run validators, aggregate results
# PostToolUse protocol: findings on stderr, exit MAX_EXIT
MAX_EXIT=0
ALL_FINDINGS=""

run_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  output=$("$func" 2>&1) || rc=$?
  if [ "$rc" -gt 0 ] && [ -n "$output" ]; then
    ALL_FINDINGS="${ALL_FINDINGS}${output}\n"
    [ "$rc" -gt "$MAX_EXIT" ] && MAX_EXIT=$rc
    record_hook_outcome "$name" "PostToolUse" "warn" "Bash" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "PostToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
  fi
}

run_validator "enforce-deploy-then-verify" validate_deploy_then_verify
run_validator "detect-unasked-deps"        validate_unasked_deps

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="warn"
  HOOK_REASON="post-bash issues detected"
fi

record_hook_outcome "post-bash-gate" "PostToolUse" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "Bash" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
