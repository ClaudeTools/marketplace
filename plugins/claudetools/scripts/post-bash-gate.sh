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
  record_hook_outcome "$name" "PostToolUse" "$decision" "Bash" "" "" "$MODEL_FAMILY"
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "post-bash-gate" "$name" "$decision" "$_duration_ms" "$output" 2>/dev/null || true
}

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
