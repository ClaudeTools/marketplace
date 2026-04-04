#!/usr/bin/env bash
# ensure-srcpilot.sh — Install srcpilot into the plugin's node_modules if not globally available.
# Priority: global install > plugin-local install. Never conflicts with user's existing install.

# If srcpilot is already globally installed, nothing to do
command -v srcpilot &>/dev/null && exit 0

# If plugin-local binary already exists, nothing to do
LOCAL_BIN="${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot"
[[ -f "$LOCAL_BIN" ]] && exit 0

# Install locally into the plugin directory (no global side effects)
if command -v npm &>/dev/null; then
  npm install --prefix "$CLAUDE_PLUGIN_ROOT" --no-audit --no-fund --loglevel=error 2>/dev/null || true
fi

exit 0
