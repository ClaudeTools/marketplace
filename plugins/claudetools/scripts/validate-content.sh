#!/bin/bash
# PostToolUse:Edit|Write dispatcher — runs stubs, secrets, localhost, and mocks validators in a single pass
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

DISPATCHER_EVENT="PostToolUse"
DISPATCHER_TOOL=""
DISPATCHER_NAME="validate-content"
DISPATCHER_MODEL_FAMILY="$MODEL_FAMILY"
source "$SCRIPT_DIR/lib/dispatcher.sh"

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
