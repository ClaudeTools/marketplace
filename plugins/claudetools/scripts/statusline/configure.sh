#!/usr/bin/env bash
# configure.sh — SessionStart hook: auto-configure statusline in ~/.claude/settings.json
# - Installs statusline if none is configured
# - Auto-repairs broken configs from the v5.1.0 bug (literal ${CLAUDE_PLUGIN_ROOT})
# Always exits 0 to never block session startup.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

# Graceful degradation if jq or CLAUDE_PLUGIN_ROOT is missing
command -v jq &>/dev/null || exit 0
[[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || exit 0

# Resolve the absolute path at hook runtime (settings.json doesn't expand env vars)
RENDER_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/statusline/render.sh"
DESIRED_CMD="bash $RENDER_SCRIPT"

# Ensure settings.json exists
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

trap 'rm -f "${SETTINGS}.tmp"' EXIT

existing=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || true

# Case 1: No statusline at all — install ours
if ! jq -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
  jq --arg cmd "$DESIRED_CMD" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  exit 0
fi

# Case 2: Broken config — contains literal '${CLAUDE_PLUGIN_ROOT}' (v5.1.0 bug)
if [[ "$existing" == *'${CLAUDE_PLUGIN_ROOT}'* ]]; then
  jq --arg cmd "$DESIRED_CMD" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  exit 0
fi

# Case 3: Our statusline but plugin moved (e.g., reinstall) — update path
if [[ "$existing" == *"statusline/render.sh"* && ! -f "${existing#bash }" ]]; then
  jq --arg cmd "$DESIRED_CMD" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  exit 0
fi

# Case 4: User has their own statusline (ccstatusline, custom script, etc.) — don't touch
exit 0
