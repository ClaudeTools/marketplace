#!/usr/bin/env bash
# PostToolUse:Edit|Write hook — incrementally re-indexes edited source files
# Runs async with timeout=5. Always exits 0.
# Edit event tracking is handled separately by track-file-edits.sh (sync).

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only re-index supported source files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py)
    ;;
  *)
    exit 0
    ;;
esac

PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/../codebase-pilot/dist/cli.js"

if [ ! -f "$CLI" ]; then
  exit 0
fi

# Convert absolute path to relative (portable — no realpath dependency)
REL_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
if [ "$REL_PATH" = "$FILE_PATH" ]; then
  # Fallback: try python3, then use as-is
  REL_PATH=$(python3 -c "import os; print(os.path.relpath('$FILE_PATH', '$PROJECT_ROOT'))" 2>/dev/null || echo "$FILE_PATH")
fi

node "$CLI" index-file "$REL_PATH" --project "$PROJECT_ROOT" 2>/dev/null >/dev/null || true

exit 0
