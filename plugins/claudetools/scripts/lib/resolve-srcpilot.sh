#!/usr/bin/env bash
# resolve-srcpilot.sh — Set SRCPILOT to the right binary path.
# Sources into other scripts. Call once at the top after CLAUDE_PLUGIN_ROOT is available.

if command -v srcpilot &>/dev/null; then
  SRCPILOT="srcpilot"
elif [[ -f "${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot" ]]; then
  SRCPILOT="${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot"
else
  SRCPILOT="srcpilot"  # will fail gracefully if truly missing
fi

export SRCPILOT
