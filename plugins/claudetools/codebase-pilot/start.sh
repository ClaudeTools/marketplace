#!/usr/bin/env bash
# Bootstrap wrapper: install deps if missing, then start the MCP server.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$DIR/node_modules" ]]; then
  if command -v npm &>/dev/null; then
    (cd "$DIR" && npm install --production --no-audit --no-fund 2>/dev/null) || true
  fi
fi

exec node "$DIR/dist/cli.js" mcp-server "$@"
