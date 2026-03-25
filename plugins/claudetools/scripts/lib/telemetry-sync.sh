#!/bin/bash
# telemetry-sync.sh — Background batch uploader for events.jsonl
# Sources telemetry.sh for paths. Called from session-end-dispatcher.

source "$(dirname "${BASH_SOURCE[0]}")/portable-lock.sh"

telemetry_sync() {
  local events_file="${_TELEMETRY_EVENTS_FILE:-}"
  [ -z "$events_file" ] && _telemetry_ensure_init 2>/dev/null || true
  events_file="${_TELEMETRY_EVENTS_FILE:-}"
  [ -z "$events_file" ] || [ ! -f "$events_file" ] || [ ! -s "$events_file" ] && return 0

  command -v curl &>/dev/null || return 0

  local lock_file="${events_file}.sync.lock"
  local tmp_file="${events_file}.tmp.$$"
  local batch_size=100
  local endpoint="https://telemetry.claudetools.com/v1/events"

  # Skip if another sync is running
  portable_trylock "$lock_file" || return 0

  local total_lines
  total_lines=$(wc -l < "$events_file" 2>/dev/null || echo 0)
  if [ "$total_lines" -eq 0 ]; then
    portable_unlock "$lock_file"
    return 0
  fi

  local offset=0
  while [ "$offset" -lt "$total_lines" ]; do
    local batch
    batch=$(sed -n "$((offset+1)),$((offset+batch_size))p" "$events_file" 2>/dev/null)
    [ -z "$batch" ] && break

    local http_code
    http_code=$(echo "$batch" | curl -s -o /dev/null -w '%{http_code}' \
      --connect-timeout 5 --max-time 10 \
      -X POST -H "Content-Type: application/x-ndjson" \
      --data-binary @- "$endpoint" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      offset=$((offset + batch_size))
    else
      hook_log "telemetry-sync: batch failed (HTTP $http_code), $((total_lines - offset)) events pending" 2>/dev/null || true
      break
    fi
  done

  # Remove synced lines
  if [ "$offset" -gt 0 ]; then
    sed -n "$((offset+1)),\$p" "$events_file" > "$tmp_file" 2>/dev/null
    mv -f "$tmp_file" "$events_file" 2>/dev/null || true
  fi
  rm -f "$tmp_file" 2>/dev/null || true

  portable_unlock "$lock_file"
}
