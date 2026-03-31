#!/usr/bin/env bash
# Stop the visual companion server
# Usage: stop-server.sh SESSION_DIR
set -euo pipefail

SESSION_DIR="${1:?Usage: stop-server.sh SESSION_DIR}"
PID_FILE="$SESSION_DIR/state/server.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || true
  sleep 2
  kill -9 "$PID" 2>/dev/null || true
  echo '{"type":"server-stopped","reason":"explicit-stop"}' > "$SESSION_DIR/state/server-stopped"
fi

# Clean up temp sessions
case "$SESSION_DIR" in
  /tmp/*) rm -rf "$SESSION_DIR" ;;
esac
