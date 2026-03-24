#!/usr/bin/env bash
# change-impact.sh — Show what breaks if a symbol changes
# Usage: change-impact.sh <symbol-name> [project-root]
set -uo pipefail

SYMBOL="${1:?Usage: change-impact.sh <symbol-name> [project-root]}"
PROJECT="${2:-}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CLI="node ${PLUGIN_ROOT}/codebase-pilot/dist/cli.js"

if [ -n "$PROJECT" ]; then
  export CODEBASE_PILOT_PROJECT_ROOT="$PROJECT"
fi

$CLI change-impact "$SYMBOL"
