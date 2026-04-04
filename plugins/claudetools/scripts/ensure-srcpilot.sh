#!/usr/bin/env bash
# ensure-srcpilot.sh — Install srcpilot into the plugin's node_modules if not globally available.
# Also runs `srcpilot setup --agent claude-code -g -y` on install or version change.
# Priority: global install > plugin-local install. Never conflicts with user's existing install.

SETUP_MARKER="${CLAUDE_PLUGIN_ROOT}/.srcpilot-setup-version"
LOCAL_BIN="${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot"

# Install locally if srcpilot is not globally available
if ! command -v srcpilot &>/dev/null; then
  if [[ ! -f "$LOCAL_BIN" ]] && command -v npm &>/dev/null; then
    npm install --prefix "$CLAUDE_PLUGIN_ROOT" --no-audit --no-fund --loglevel=error 2>/dev/null || true
  fi
fi

# Run global setup only when srcpilot is in PATH (global install).
# Skipped for plugin-local installs — those binaries are not in PATH so the
# installed skill would reference commands the user can't run directly.
if command -v srcpilot &>/dev/null; then
  CURRENT_VERSION=$(srcpilot --version 2>/dev/null || echo "unknown")
  STORED_VERSION=$(cat "$SETUP_MARKER" 2>/dev/null || echo "")
  if [[ "$CURRENT_VERSION" != "$STORED_VERSION" ]]; then
    srcpilot setup --agent claude-code -g -y 2>/dev/null || true
    echo "$CURRENT_VERSION" > "$SETUP_MARKER"
  fi
fi

exit 0
