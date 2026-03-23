#!/bin/bash
# hook-input.sh — Shared input library for content-checking hooks
# Usage: source "$(dirname "$0")/lib/hook-input.sh" && hook_init
#
# Provides:
#   hook_init()           — reads stdin, sources deps, sets globals, installs EXIT trap
#   hook_get_content()    — lazy extraction of new_string/content (cached)
#   hook_get_field(path)  — arbitrary jq field from INPUT

# Resolve this file's own directory (works when sourced from any hook)
_HOOK_INPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hook_init() {
  # Read stdin once — must be called before any other output to avoid consuming stdin twice
  INPUT=$(cat 2>/dev/null || true)
  export INPUT

  # Source dependencies using paths relative to this lib/ directory
  # shellcheck source=hook-log.sh
  source "${_HOOK_INPUT_DIR}/../hook-log.sh"
  # shellcheck source=ensure-db.sh
  source "${_HOOK_INPUT_DIR}/ensure-db.sh"
  ensure_metrics_db 2>/dev/null || true
  # shellcheck source=adaptive-weights.sh
  source "${_HOOK_INPUT_DIR}/adaptive-weights.sh"
  # Structured telemetry (machine-readable events.jsonl)
  source "${_HOOK_INPUT_DIR}/telemetry.sh" 2>/dev/null || true

  # Detect model family and export globals hooks depend on
  MODEL_FAMILY=$(detect_model_family)
  export MODEL_FAMILY

  # Default decision/reason so trap always has values
  export HOOK_DECISION="${HOOK_DECISION:-allow}"
  export HOOK_REASON="${HOOK_REASON:-}"

  # Install exit trap before any early-return paths
  trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

  hook_log "invoked"

  # Extract common file fields — cover all field names used across hooks
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_response.filePath // empty' 2>/dev/null || true)
  export FILE_PATH

  # Derived file metadata (safe when FILE_PATH is empty)
  BASENAME="${FILE_PATH##*/}"
  export BASENAME

  # Extension without leading dot (e.g. "ts", "py", "")
  if [[ "$BASENAME" == *.* ]]; then
    FILE_EXT="${BASENAME##*.}"
  else
    FILE_EXT=""
  fi
  export FILE_EXT

  emit_event "$HOOK_NAME" "hook_init" "allow" 2>/dev/null || true
}

# Lazy content extraction — call only when you need the written content
_HOOK_CONTENT_LOADED=0
_HOOK_CONTENT=""

hook_get_content() {
  if [[ "$_HOOK_CONTENT_LOADED" == "0" ]]; then
    _HOOK_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null || true)
    _HOOK_CONTENT_LOADED=1
  fi
  echo "$_HOOK_CONTENT"
}

# Arbitrary field extraction from INPUT
# Usage: value=$(hook_get_field '.tool_input.cwd')
hook_get_field() {
  local jq_path="$1"
  echo "$INPUT" | jq -r "${jq_path} // empty" 2>/dev/null || true
}
