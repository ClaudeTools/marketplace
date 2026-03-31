#!/usr/bin/env bash
# Start the visual companion server
# Usage: start-server.sh --project-dir /path/to/project [--host 0.0.0.0] [--url-host localhost] [--foreground]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse arguments
PROJECT_DIR=""
HOST="127.0.0.1"
URL_HOST=""
FOREGROUND=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --url-host) URL_HOST="$2"; shift 2 ;;
    --foreground) FOREGROUND=1; shift ;;
    *) shift ;;
  esac
done

[ -z "$URL_HOST" ] && URL_HOST="$HOST"

# Create session directory
SESSION_ID="$$-$(date +%s)"
if [ -n "$PROJECT_DIR" ]; then
  SESSION_DIR="$PROJECT_DIR/.claudetools/design/$SESSION_ID"
else
  SESSION_DIR="/tmp/claudetools-design-$SESSION_ID"
fi

CONTENT_DIR="$SESSION_DIR/content"
STATE_DIR="$SESSION_DIR/state"
mkdir -p "$CONTENT_DIR" "$STATE_DIR"

# Auto-detect foreground mode (Windows/MSYS, CI environments)
[[ "${MSYSTEM:-}${MSYS:-}${CODEX_CI:-}" != "" ]] && FOREGROUND=1

export BRAINSTORM_DIR="$SESSION_DIR"
export BRAINSTORM_HOST="$HOST"
export BRAINSTORM_URL_HOST="$URL_HOST"
export BRAINSTORM_OWNER_PID="$PPID"

if [ "$FOREGROUND" -eq 1 ]; then
  node "$SCRIPT_DIR/server.cjs"
else
  nohup node "$SCRIPT_DIR/server.cjs" > "$STATE_DIR/server.log" 2>&1 &
  # Wait for server to start and write server-info (up to 3 seconds)
  for i in $(seq 1 30); do
    [ -f "$STATE_DIR/server-info" ] && break
    sleep 0.1
  done
  [ -f "$STATE_DIR/server-info" ] && cat "$STATE_DIR/server-info"
fi
