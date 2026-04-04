#!/usr/bin/env bash
# ensure-srcpilot.sh — Install srcpilot into the plugin's node_modules if not globally available.
# Also runs `srcpilot setup --agent claude-code -g -y` on install or version change.
# Priority: global install > plugin-local install. Never conflicts with user's existing install.

SETUP_MARKER="${CLAUDE_PLUGIN_ROOT}/.srcpilot-setup-version"
LOCAL_BIN="${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot"

# Resolve which binary to use
if command -v srcpilot &>/dev/null; then
  SRCPILOT_BIN="srcpilot"
elif [[ -f "$LOCAL_BIN" ]]; then
  SRCPILOT_BIN="$LOCAL_BIN"
else
  SRCPILOT_BIN=""
fi

# Install locally if not available anywhere
if [[ -z "$SRCPILOT_BIN" ]]; then
  if command -v npm &>/dev/null; then
    npm install --prefix "$CLAUDE_PLUGIN_ROOT" --no-audit --no-fund --loglevel=error 2>/dev/null || true
    [[ -f "$LOCAL_BIN" ]] && SRCPILOT_BIN="$LOCAL_BIN"
  fi
fi

# Run setup if srcpilot is available and version has changed (or never run)
if [[ -n "$SRCPILOT_BIN" ]]; then
  CURRENT_VERSION=$("$SRCPILOT_BIN" --version 2>/dev/null || echo "unknown")
  STORED_VERSION=$(cat "$SETUP_MARKER" 2>/dev/null || echo "")
  if [[ "$CURRENT_VERSION" != "$STORED_VERSION" ]]; then
    "$SRCPILOT_BIN" setup --agent claude-code -g -y 2>/dev/null || true
    echo "$CURRENT_VERSION" > "$SETUP_MARKER"
  fi
fi

exit 0
