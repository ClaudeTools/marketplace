#!/usr/bin/env bash
# complexity-report.sh — AST-aware function complexity analysis
# Usage: complexity-report.sh [--threshold N] [project-root]
set -uo pipefail

THRESHOLD=50
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      THRESHOLD="${2:?--threshold requires a number}"
      shift 2
      ;;
    *)
      PROJECT="$1"
      shift
      ;;
  esac
done

PROJECT="${PROJECT:-$(pwd)}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CLI="node ${PLUGIN_ROOT}/codebase-pilot/dist/cli.js"

export CODEBASE_PILOT_PROJECT_ROOT="$PROJECT"

echo "=== Complexity Report (threshold: ${THRESHOLD} lines) ==="
echo ""

# Query the index for all functions with line ranges
DBPATH="${PROJECT}/.codeindex/db.sqlite"
if [ ! -f "$DBPATH" ]; then
  echo "No index found. Run: codebase-pilot index"
  exit 1
fi

# Get functions with their line counts from the index
sqlite3 -separator '|' "$DBPATH" "
  SELECT f.path, s.name, s.kind, s.line, s.end_line,
         COALESCE(s.end_line - s.line + 1, 0) as line_count
  FROM symbols s
  JOIN files f ON s.file_id = f.id
  WHERE s.kind IN ('function', 'method')
    AND s.end_line IS NOT NULL
    AND (s.end_line - s.line + 1) >= ${THRESHOLD}
  ORDER BY line_count DESC
  LIMIT 50
" 2>/dev/null | while IFS='|' read -r filepath name kind start_line end_line line_count; do
  # Check nesting depth by counting indentation in the source
  NESTING=""
  if [ -f "${PROJECT}/${filepath}" ]; then
    MAX_INDENT=$(sed -n "${start_line},${end_line}p" "${PROJECT}/${filepath}" 2>/dev/null \
      | grep -v '^\s*$' \
      | sed 's/[^ \t].*//' \
      | awk '{ gsub(/\t/, "    "); print length }' \
      | sort -rn \
      | head -1)
    if [ -n "$MAX_INDENT" ] && [ "$MAX_INDENT" -gt 16 ]; then
      NESTING=" [deep nesting]"
    fi
  fi
  echo "  ${filepath}:${start_line} — ${kind} ${name} (${line_count} lines)${NESTING}"
done

TOTAL=$(sqlite3 "$DBPATH" "
  SELECT COUNT(*)
  FROM symbols s
  WHERE s.kind IN ('function', 'method')
    AND s.end_line IS NOT NULL
    AND (s.end_line - s.line + 1) >= ${THRESHOLD}
" 2>/dev/null)

echo ""
echo "Total: ${TOTAL:-0} function(s) over ${THRESHOLD} lines"
