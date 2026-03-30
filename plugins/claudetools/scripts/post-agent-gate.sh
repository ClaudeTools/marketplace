#!/bin/bash
# PostToolUse:Agent dispatcher — runs agent-output and semantic-agent validators
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/lib/hook-skip.sh"
source "$SCRIPT_DIR/validators/agent-output.sh"
source "$SCRIPT_DIR/validators/semantic-agent.sh"

# Phase 3: Run validators, aggregate results
# PostToolUse protocol: findings on stderr, exit MAX_EXIT
MAX_EXIT=0
ALL_FINDINGS=""

DISPATCHER_EVENT="PostToolUse"
DISPATCHER_TOOL="Agent"
DISPATCHER_NAME="post-agent-gate"
DISPATCHER_MODEL_FAMILY="$MODEL_FAMILY"
source "$SCRIPT_DIR/lib/dispatcher.sh"

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
