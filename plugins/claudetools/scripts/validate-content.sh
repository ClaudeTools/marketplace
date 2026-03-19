#!/bin/bash
# PostToolUse:Edit|Write dispatcher — validates content in a single pass
# Replaces: verify-no-stubs.sh, detect-hardcoded-secrets.sh, detect-localhost-in-config.sh, check-mock-in-prod.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Fast-path skip
source "$SCRIPT_DIR/lib/hook-skip.sh"
if should_skip_content_check "$FILE_PATH"; then
  record_hook_outcome "validate-content" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
  exit 0
fi

# Phase 3: Source validators
source "$SCRIPT_DIR/validators/stubs.sh"
source "$SCRIPT_DIR/validators/secrets.sh"
source "$SCRIPT_DIR/validators/localhost.sh"
source "$SCRIPT_DIR/validators/mocks.sh"

# Phase 4: Run validators, aggregate results
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
    record_hook_outcome "$name" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_event "$name" "validator_run" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" '{"dispatcher":"validate-content"}' 2>/dev/null || true
}

run_validator "verify-no-stubs" validate_stubs
run_validator "detect-hardcoded-secrets" validate_secrets
run_validator "detect-localhost-in-config" validate_localhost
run_validator "check-mock-in-prod" validate_mocks

# Phase 5: Emit aggregated findings
if [ -n "$ALL_FINDINGS" ]; then
  echo -e "$ALL_FINDINGS" >&2
  HOOK_DECISION="warn"
  HOOK_REASON="content issues in $BASENAME"
fi

record_hook_outcome "validate-content" "PostToolUse" "$( [ "$MAX_EXIT" -gt 0 ] && echo warn || echo allow )" "" "" "" "$MODEL_FAMILY"
exit $MAX_EXIT
