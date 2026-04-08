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

# --- Autocompact workaround for 1M models ---
# CC bug: getEffectiveWindow() returns 200K for [1m] models, causing compaction
# at ~167K tokens instead of ~967K. CLAUDE_CODE_AUTO_COMPACT_WINDOW overrides the
# effective window used by the compaction engine. Setting to 1M is safe for all
# models — the value is capped at the model's actual context window.
# See: github.com/anthropics/claude-code/issues/36014
current_window=$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // empty' "$SETTINGS" 2>/dev/null) || true
if [[ -z "$current_window" ]]; then
  jq '.env = (.env // {}) + {"CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000", "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "95"}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
fi

# --- User config migration ---
# If user has a statusline.json with an old default widget list, update it to the current defaults.
# Only migrates if the list exactly matches a known old default (user hasn't customized).
USER_CONFIG="$HOME/.config/claudetools/statusline.json"
DEFAULT_CONFIG="${CLAUDE_PLUGIN_ROOT}/scripts/statusline/defaults.json"

if [[ -f "$USER_CONFIG" && -f "$DEFAULT_CONFIG" ]]; then
  current_widgets=$(jq -c '.widgets' "$USER_CONFIG" 2>/dev/null) || true
  desired_widgets=$(jq -c '.widgets' "$DEFAULT_CONFIG" 2>/dev/null) || true

  # Known old defaults that should be auto-migrated (exact order as shipped)
  OLD_V1='["model","git","context","cost","speed","duration","worktree"]'
  OLD_V2='["model","git","context","session","weekly","duration","worktree"]'

  if [[ ("$current_widgets" == "$OLD_V1" || "$current_widgets" == "$OLD_V2") && "$current_widgets" != "$desired_widgets" ]]; then
    # Preserve user's separator and color prefs, only update widgets
    jq --argjson widgets "$(jq '.widgets' "$DEFAULT_CONFIG")" \
      '.widgets = $widgets' \
      "$USER_CONFIG" > "${USER_CONFIG}.tmp" && mv "${USER_CONFIG}.tmp" "$USER_CONFIG"
  fi
fi

exit 0
