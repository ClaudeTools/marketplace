#!/usr/bin/env bash
# dead-code.sh — Find exported symbols never imported anywhere
# Usage: dead-code.sh [--all] [--json] [project-root]
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CLI="node ${PLUGIN_ROOT}/codebase-pilot/dist/cli.js"

ARGS=()
PROJECT=""

for arg in "$@"; do
  case "$arg" in
    --all|--json) ARGS+=("$arg") ;;
    *) PROJECT="$arg" ;;
  esac
done

if [ -n "$PROJECT" ]; then
  export CODEBASE_PILOT_PROJECT_ROOT="$PROJECT"
fi

$CLI dead-code
