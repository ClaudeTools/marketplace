#!/bin/bash
# PostToolUse:Agent dispatcher
# Replaces: agent-output.sh, semantic-agent.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/agent-output.sh"
source "$SCRIPT_DIR/validators/semantic-agent.sh"

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
  if [ "$rc" -gt 0 ] && [ -n "$output" ]; then
    ALL_FINDINGS="${ALL_FINDINGS}${output}\n"
    [ "$rc" -gt "$MAX_EXIT" ] && MAX_EXIT=$rc
    record_hook_outcome "$name" "PostToolUse" "warn" "Agent" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "PostToolUse" "allow" "Agent" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_event "$name" "validator_run" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" '{"dispatcher":"post-agent-gate"}' 2>/dev/null || true
}

run_validator "agent-output"   validate_agent_output
run_validator "semantic-agent" validate_semantic_agent

# Phase 4: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="warn"
  HOOK_REASON="post-agent issues detected"
fi

record_hook_outcome "post-agent-gate" "PostToolUse" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "Agent" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
