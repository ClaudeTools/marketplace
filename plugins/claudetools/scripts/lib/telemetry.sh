#!/usr/bin/env bash
# telemetry.sh — Structured local event logging for claudetools hooks
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/telemetry.sh"
# Then call: emit_event "component" "event" "decision" "duration_ms" '{"key":"val"}'
#
# Appends JSONL to plugin/logs/events.jsonl — no jq, no subshells, no external deps
# All globals cached after first _telemetry_ensure_init call

# Cached globals — exported so subshells inherit without re-init
_TELEMETRY_INSTALL_ID="${_TELEMETRY_INSTALL_ID:-}"
_TELEMETRY_VERSION="${_TELEMETRY_VERSION:-}"
_TELEMETRY_OS="${_TELEMETRY_OS:-}"
_TELEMETRY_EVENTS_FILE="${_TELEMETRY_EVENTS_FILE:-}"

_telemetry_ensure_init() {
  # Return fast if already initialised
  [ -n "${_TELEMETRY_INSTALL_ID:-}" ] && return 0

  # Resolve stable plugin root — mirrors ensure-db.sh logic
  local _telem_root="${_plugin_root:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"

  # Versioned install path — use parent directory (plugin name level) for stable data dir
  if [[ "$_telem_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    _telem_root="$(dirname "$_telem_root")"
  fi

  local data_dir="${_telem_root}/data"
  local id_file="${data_dir}/.install-id"

  # Persist install_id across upgrades
  if [ -f "$id_file" ]; then
    _TELEMETRY_INSTALL_ID=$(cat "$id_file" 2>/dev/null || echo "unknown")
  else
    mkdir -p "$data_dir" 2>/dev/null || true
    _TELEMETRY_INSTALL_ID=$(
      uuidgen 2>/dev/null \
      || cat /proc/sys/kernel/random/uuid 2>/dev/null \
      || printf '%s-%s-%s' "$(date +%s)" "$$" "$(hostname -s 2>/dev/null || echo unknown)" \
           | sha256sum 2>/dev/null | cut -c1-36 \
      || echo "unknown"
    )
    printf '%s\n' "$_TELEMETRY_INSTALL_ID" > "$id_file" 2>/dev/null || true
  fi

  # Plugin version — read once from plugin.json via grep (no jq)
  local pjson="${_telem_root}/.claude-plugin/plugin.json"
  _TELEMETRY_VERSION=$(
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pjson" 2>/dev/null \
      | grep -o '"[^"]*"$' \
      | tr -d '"' \
    || echo "unknown"
  )

  # OS identifier
  _TELEMETRY_OS=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")

  # Events log path — ensure directory exists
  local log_dir="${_telem_root}/logs"
  mkdir -p "$log_dir" 2>/dev/null || true
  _TELEMETRY_EVENTS_FILE="${log_dir}/events.jsonl"

  # Log rotation at 10MB (cross-platform stat)
  if [ -f "$_TELEMETRY_EVENTS_FILE" ]; then
    local size
    size=$(stat -f%z "$_TELEMETRY_EVENTS_FILE" 2>/dev/null \
           || stat -c%s "$_TELEMETRY_EVENTS_FILE" 2>/dev/null \
           || echo 0)
    if [ "$size" -gt 10485760 ]; then
      mv -f "$_TELEMETRY_EVENTS_FILE" "${_TELEMETRY_EVENTS_FILE}.1" 2>/dev/null || true
    fi
  fi

  export _TELEMETRY_INSTALL_ID _TELEMETRY_VERSION _TELEMETRY_OS _TELEMETRY_EVENTS_FILE
}

# emit_event component event decision duration_ms extra_json
#   component   — hook/script name (required)
#   event       — event label, e.g. "hook_init", "decision_block" (optional)
#   decision    — "allow" | "block" | "warn" (optional)
#   duration_ms — integer milliseconds (optional, defaults to 0)
#   extra_json  — raw JSON object for additional fields (optional, defaults to {})
emit_event() {
  # Guard: do nothing if events file can't be initialised
  _telemetry_ensure_init 2>/dev/null || return 0

  local component="${1:-unknown}"
  local event="${2:-}"
  local decision="${3:-}"
  local duration_ms="${4:-0}"
  local extra="${5:-}"
  [ -z "$extra" ] && extra='{}'

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # printf-only JSON — no jq, no subshells beyond the date above
  printf '{"ts":"%s","install_id":"%s","plugin_version":"%s","component":"%s","event":"%s","decision":"%s","duration_ms":%s,"model_family":"%s","os":"%s","extra":%s}\n' \
    "$ts" \
    "$_TELEMETRY_INSTALL_ID" \
    "$_TELEMETRY_VERSION" \
    "$component" \
    "$event" \
    "$decision" \
    "$duration_ms" \
    "${MODEL_FAMILY:-unknown}" \
    "$_TELEMETRY_OS" \
    "$extra" \
    >> "$_TELEMETRY_EVENTS_FILE" 2>/dev/null || true
}
