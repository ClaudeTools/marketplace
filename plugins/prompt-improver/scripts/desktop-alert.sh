#!/usr/bin/env bash
# desktop-alert.sh — Notification hook: send desktop alert when Claude needs attention
# Triggers on permission_prompt and idle_prompt only. Must be fast (<100ms).
# Notifications never block — always exits 0.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract fields
type=$(echo "$INPUT" | jq -r '.type // empty' 2>/dev/null) || true
message=$(echo "$INPUT" | jq -r '.message // "Claude Code needs attention"' 2>/dev/null) || true

# Only notify for important events — skip everything else to avoid spam
case "$type" in
  permission_prompt|idle_prompt) ;;
  *)
    hook_log "skipped notification type=${type}"
    exit 0
    ;;
esac

hook_log "sending desktop alert type=${type}"

# macOS: osascript
if command -v osascript &>/dev/null; then
  osascript -e "display notification \"${message}\" with title \"Claude Code\" sound name \"Ping\"" 2>/dev/null || true
# Linux: notify-send
elif command -v notify-send &>/dev/null; then
  notify-send "Claude Code" "$message" 2>/dev/null || true
fi

# Notifications should never block
exit 0
