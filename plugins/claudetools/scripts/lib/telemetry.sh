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

# emit_session_start — Rich environment snapshot emitted once at SessionStart
# Collects: Claude Code version, other plugins, total hook count, shell, node version,
#           team mode, project languages, memory file count
emit_session_start() {
  _telemetry_ensure_init 2>/dev/null || return 0

  local claude_version node_version shell_name total_hooks team_mode
  local plugin_list memory_count project_langs

  # Claude Code version
  claude_version=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")

  # Node version
  node_version=$(node --version 2>/dev/null | tr -d 'v' || echo "unknown")

  # Shell
  shell_name=$(basename "${SHELL:-unknown}" 2>/dev/null || echo "unknown")

  # Other installed plugins (names only — from plugins cache or .claude/plugins)
  plugin_list="[]"
  if [ -d "$HOME/.claude/plugins" ]; then
    plugin_list=$(ls "$HOME/.claude/plugins/" 2>/dev/null | head -20 | jq -R . 2>/dev/null | jq -sc . 2>/dev/null || echo "[]")
  fi

  # Total hook count across all plugins (from settings + plugin hooks)
  total_hooks=$(grep -r '"command"' "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$HOME/.claude/projects/"*/settings.json "$HOME/.claude/projects/"*/settings.local.json "${CLAUDE_PLUGIN_ROOT:-}/hooks/hooks.json" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

  # Team session detection
  team_mode="solo"
  [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "1" ] && team_mode="teams"

  # Project language breakdown from codebase-pilot index
  project_langs="{}"
  local db_path="${CLAUDE_PLUGIN_ROOT:-}/data/codeindex.db"
  if [ -f "$db_path" ] && command -v sqlite3 &>/dev/null; then
    project_langs=$(sqlite3 "$db_path" "SELECT json_group_object(language, cnt) FROM (SELECT language, COUNT(*) as cnt FROM files WHERE language IS NOT NULL GROUP BY language ORDER BY cnt DESC LIMIT 10);" 2>/dev/null || echo "{}")
    [ -z "$project_langs" ] && project_langs="{}"
  fi

  # Memory file count
  local memory_dir="$HOME/.claude/projects/$(pwd | sed 's|^/|-|' | tr '/' '-')/memory"
  memory_count=0
  if [ -d "$memory_dir" ]; then
    memory_count=$(find "$memory_dir" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  fi

  emit_event "session" "session_start" "allow" "0" \
    "$(printf '{"claude_version":"%s","node_version":"%s","shell":"%s","total_hooks":%s,"team_mode":"%s","plugins":%s,"project_languages":%s,"memory_count":%s}' \
      "$claude_version" "$node_version" "$shell_name" "$total_hooks" \
      "$team_mode" "$plugin_list" "$project_langs" "$memory_count")"
}

# emit_session_end — Session summary emitted once at SessionEnd
# Collects: session metrics (tool calls, edits, failures, churn, tasks, duration),
#           hook decision totals, dispatcher fire counts
emit_session_end() {
  _telemetry_ensure_init 2>/dev/null || return 0

  local session_id="${1:-unknown}"
  local total_calls=0 total_failures=0 total_edits=0 churn_rate=0
  local tasks_completed=0 duration_min=0
  local hook_blocks=0 hook_warns=0 hook_allows=0

  # Session metrics from metrics.db
  if command -v sqlite3 &>/dev/null && [ -f "${METRICS_DB:-}" ]; then
    local row
    row=$(sqlite3 "$METRICS_DB" \
      "SELECT total_tool_calls, total_failures, total_edits, edit_churn_rate, tasks_completed, duration_minutes
       FROM session_metrics WHERE session_id='$session_id' LIMIT 1;" 2>/dev/null || true)
    if [ -n "$row" ]; then
      total_calls=$(echo "$row" | cut -d'|' -f1)
      total_failures=$(echo "$row" | cut -d'|' -f2)
      total_edits=$(echo "$row" | cut -d'|' -f3)
      churn_rate=$(echo "$row" | cut -d'|' -f4)
      tasks_completed=$(echo "$row" | cut -d'|' -f5)
      duration_min=$(echo "$row" | cut -d'|' -f6)
    fi

    # Hook decision totals for this session
    hook_blocks=$(sqlite3 "$METRICS_DB" \
      "SELECT COUNT(*) FROM hook_outcomes WHERE session_id='$session_id' AND decision='block';" 2>/dev/null || echo "0")
    hook_warns=$(sqlite3 "$METRICS_DB" \
      "SELECT COUNT(*) FROM hook_outcomes WHERE session_id='$session_id' AND decision='warn';" 2>/dev/null || echo "0")
    hook_allows=$(sqlite3 "$METRICS_DB" \
      "SELECT COUNT(*) FROM hook_outcomes WHERE session_id='$session_id' AND decision='allow';" 2>/dev/null || echo "0")
  fi

  # Dispatcher fire counts from events.jsonl (current session)
  local dispatcher_counts="{}"
  if [ -f "${_TELEMETRY_EVENTS_FILE:-}" ]; then
    dispatcher_counts=$(grep '"event":"validator_run"' "$_TELEMETRY_EVENTS_FILE" 2>/dev/null \
      | grep -o '"component":"[^"]*"' \
      | sort | uniq -c | sort -rn | head -20 \
      | awk '{gsub(/"component":"/,"",$2); gsub(/"/,"",$2); printf "%s\"%s\":%s", (NR>1?",":""), $2, $1}' \
      | awk '{print "{"$0"}"}' 2>/dev/null || echo "{}")
    [ -z "$dispatcher_counts" ] && dispatcher_counts="{}"
  fi

  emit_event "session" "session_end" "allow" "0" \
    "$(printf '{"session_id":"%s","total_tool_calls":%s,"total_failures":%s,"total_edits":%s,"edit_churn_rate":%s,"tasks_completed":%s,"duration_minutes":%s,"hook_blocks":%s,"hook_warns":%s,"hook_allows":%s,"dispatcher_fires":%s}' \
      "$session_id" "${total_calls:-0}" "${total_failures:-0}" "${total_edits:-0}" \
      "${churn_rate:-0}" "${tasks_completed:-0}" "${duration_min:-0}" \
      "${hook_blocks:-0}" "${hook_warns:-0}" "${hook_allows:-0}" "$dispatcher_counts")"
}

# emit_error — Error event emitted on tool/hook failures
# Collects: tool name, error class, catching hook, whether user retried
emit_error() {
  local tool_name="${1:-unknown}"
  local error_class="${2:-unknown}"
  local catching_hook="${3:-none}"
  local retried="${4:-false}"

  emit_event "error" "tool_failure" "error" "0" \
    "$(printf '{"tool":"%s","error_class":"%s","catching_hook":"%s","retried":%s}' \
      "$tool_name" "$error_class" "$catching_hook" "$retried")"
}
