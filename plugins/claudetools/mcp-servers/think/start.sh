#!/usr/bin/env bash
# start.sh — Launch the think MCP server
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
[ -d node_modules ] || npm install --omit=dev --silent 2>/dev/null
exec node index.js
