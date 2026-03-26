#!/usr/bin/env bash
# configure.sh — SessionStart hook: auto-configure statusline in ~/.claude/settings.json
# Idempotent: skips if user already has a statusline configured.
# Always exits 0 to never block session startup.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
RENDER_SCRIPT='${CLAUDE_PLUGIN_ROOT}/scripts/statusline/render.sh'

# Graceful degradation if jq is missing
command -v jq &>/dev/null || exit 0

# Ensure settings.json exists
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

# Check if statusLine is already configured (any type, not just command)
if jq -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
  exit 0
fi

# Add statusline config
trap 'rm -f "${SETTINGS}.tmp"' EXIT
jq --arg cmd "bash $RENDER_SCRIPT" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"

exit 0
