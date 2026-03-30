#!/bin/bash
# SessionEnd dispatcher (async) — session-wrap, aggregate-session, doc-index, memory-consolidate
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
source "$SCRIPT_DIR/validators/memory-consolidate.sh"
source "$SCRIPT_DIR/lib/telemetry-sync.sh"

# Phase 3: Run all validators sequentially — errors logged but never blocking
# SessionEnd protocol: async side-effects only, exit 0 always
DISPATCHER_EVENT="SessionEnd"
DISPATCHER_TOOL=""
DISPATCHER_NAME="session-end-dispatcher"
DISPATCHER_MODEL_FAMILY="$MODEL_FAMILY"
source "$SCRIPT_DIR/lib/dispatcher.sh"

# Emit session end telemetry — include subagents (they have distinct metrics)
_sid=$(hook_get_field '.session_id' 2>/dev/null || echo "unknown")
_agent_type=$(hook_get_field '.agent_type' 2>/dev/null || echo "main")
emit_session_end "$_sid" 2>/dev/null || true

run_async_validator "session-wrap"        run_session_wrap
run_async_validator "aggregate-session"   run_aggregate_session
run_async_validator "doc-index"           run_doc_index
run_async_validator "memory-consolidate"  run_memory_consolidate
run_async_validator "telemetry-sync"      telemetry_sync

record_hook_outcome "session-end-dispatcher" "SessionEnd" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
