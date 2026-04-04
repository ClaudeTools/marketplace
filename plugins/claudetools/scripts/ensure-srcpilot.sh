#!/usr/bin/env bash
# ensure-srcpilot.sh — One-time setup: install srcpilot globally if not present.
# Runs on SessionStart as step 0. Uses a marker file to skip on repeat sessions.

MARKER="$HOME/.claudetools-srcpilot-installed"
[[ -f "$MARKER" ]] && exit 0

if command -v srcpilot &>/dev/null; then
  touch "$MARKER"
  exit 0
fi

if command -v npm &>/dev/null; then
  npm install -g srcpilot 2>/dev/null && touch "$MARKER"
fi

exit 0
