#!/bin/bash
# SessionEnd dispatcher (async)
# Replaces: session-wrap.sh, aggregate-session.sh, doc-index.sh, memory-deep.sh, memory-consolidate.sh
# Runs all side-effect validators sequentially; exits 0 always (async — errors logged, not blocking).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Single input parse
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init

# Phase 2: Source validators
source "$SCRIPT_DIR/validators/session-wrap.sh"
source "$SCRIPT_DIR/validators/aggregate-session.sh"
source "$SCRIPT_DIR/validators/doc-index.sh"
source "$SCRIPT_DIR/validators/memory-deep.sh"
source "$SCRIPT_DIR/validators/memory-consolidate.sh"
source "$SCRIPT_DIR/lib/telemetry-sync.sh"

# Phase 3: Run all validators sequentially — errors logged but never blocking
# SessionEnd protocol: async side-effects only, exit 0 always
run_async_validator() {
  local name="$1"
  local func="$2"
  local output
  local rc=0
  local _t_start
  _t_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  output=$("$func" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    hook_log "session-end: $name failed (rc=$rc): $output"
    record_hook_outcome "$name" "SessionEnd" "warn" "" "" "" "$MODEL_FAMILY"
  else
    record_hook_outcome "$name" "SessionEnd" "allow" "" "" "" "$MODEL_FAMILY"
  fi
  local _t_end _duration_ms
  _t_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)}
  _duration_ms=$(awk "BEGIN {printf \"%d\", ($_t_end - $_t_start) * 1000}" 2>/dev/null || echo 0)
  emit_validator_event "session-end-dispatcher" "$name" "$( [ $rc -gt 0 ] && echo warn || echo allow )" "$_duration_ms" "$output" 2>/dev/null || true
}

# Emit session end telemetry — include subagents (they have distinct metrics)
local _sid _agent_type
_sid=$(hook_get_field '.session_id' 2>/dev/null || echo "unknown")
_agent_type=$(hook_get_field '.agent_type' 2>/dev/null || echo "main")
emit_session_end "$_sid" 2>/dev/null || true

run_async_validator "session-wrap"        run_session_wrap
run_async_validator "aggregate-session"   run_aggregate_session
run_async_validator "doc-index"           run_doc_index
run_async_validator "memory-deep"         run_memory_deep
run_async_validator "memory-consolidate"  run_memory_consolidate
run_async_validator "telemetry-sync"      telemetry_sync

record_hook_outcome "session-end-dispatcher" "SessionEnd" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
