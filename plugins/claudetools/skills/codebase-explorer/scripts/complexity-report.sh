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

export SRCPILOT_PROJECT_ROOT="$PROJECT"

# Source pilot-query library for consistency
# shellcheck source=../../../scripts/lib/pilot-query.sh
if [ -f "${PLUGIN_ROOT}/scripts/lib/pilot-query.sh" ]; then
  # shellcheck disable=SC1090
  source "${PLUGIN_ROOT}/scripts/lib/pilot-query.sh"
fi

echo "=== Complexity Report (threshold: ${THRESHOLD} lines) ==="
echo ""

# Query the index for all functions with line ranges
DBPATH="${PROJECT}/.srcpilot/db.sqlite"
if [ ! -f "$DBPATH" ]; then
  echo "No index found. Run: srcpilot index"
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

# --- Summary Statistics ---
echo ""
echo "--- Summary Statistics ---"

TOTAL_FUNCS=$(sqlite3 "$DBPATH" "
  SELECT COUNT(*) FROM symbols
  WHERE kind IN ('function','method') AND end_line IS NOT NULL
" 2>/dev/null)

AVG_LEN=$(sqlite3 "$DBPATH" "
  SELECT ROUND(AVG(end_line - line + 1), 1)
  FROM symbols
  WHERE kind IN ('function','method') AND end_line IS NOT NULL
" 2>/dev/null)

# Median: use the row at position COUNT/2 ordered by length
MEDIAN_LEN=$(sqlite3 "$DBPATH" "
  SELECT end_line - line + 1 AS len
  FROM symbols
  WHERE kind IN ('function','method') AND end_line IS NOT NULL
  ORDER BY len
  LIMIT 1 OFFSET (
    SELECT COUNT(*)/2 FROM symbols
    WHERE kind IN ('function','method') AND end_line IS NOT NULL
  )
" 2>/dev/null)

# P95: row at position FLOOR(COUNT*0.95) ordered by length
P95_LEN=$(sqlite3 "$DBPATH" "
  SELECT end_line - line + 1 AS len
  FROM symbols
  WHERE kind IN ('function','method') AND end_line IS NOT NULL
  ORDER BY len
  LIMIT 1 OFFSET (
    SELECT MAX(CAST(COUNT(*) * 95 / 100 AS INTEGER) - 1, 0)
    FROM symbols
    WHERE kind IN ('function','method') AND end_line IS NOT NULL
  )
" 2>/dev/null)

HIGH_DENSITY_FILES=$(sqlite3 "$DBPATH" "
  SELECT COUNT(*) FROM (
    SELECT f.id FROM symbols s
    JOIN files f ON s.file_id = f.id
    WHERE s.kind IN ('function','method')
    GROUP BY f.id
    HAVING COUNT(*) > 10
  )
" 2>/dev/null)

echo "  Total functions/methods : ${TOTAL_FUNCS:-No data}"
echo "  Average length          : ${AVG_LEN:-No data} lines"
echo "  Median length           : ${MEDIAN_LEN:-No data} lines"
echo "  P95 length              : ${P95_LEN:-No data} lines"
echo "  Files with >10 functions: ${HIGH_DENSITY_FILES:-No data}"

# --- Densest Files (by function count) ---
echo ""
echo "--- Densest Files (by function count, top 10) ---"

DENSITY_RESULTS=$(sqlite3 -separator '|' "$DBPATH" "
  SELECT f.path, COUNT(*) as symbol_count,
         SUM(COALESCE(s.end_line - s.line + 1, 0)) as total_lines
  FROM symbols s JOIN files f ON s.file_id = f.id
  WHERE s.kind IN ('function', 'method')
  GROUP BY f.path
  ORDER BY symbol_count DESC LIMIT 10
" 2>/dev/null)

if [ -z "$DENSITY_RESULTS" ]; then
  echo "  No data"
else
  echo "$DENSITY_RESULTS" | while IFS='|' read -r filepath sym_count total_lines; do
    echo "  ${filepath} — ${sym_count} functions, ${total_lines} total lines"
  done
fi

# --- High-Risk: Long + Deep Nesting ---
echo ""
echo "--- High-Risk: Long + Deeply Nested (>30 lines AND nesting >4 levels) ---"

HIGH_RISK_OUTPUT=$(sqlite3 -separator '|' "$DBPATH" "
  SELECT f.path, s.name, s.kind, s.line, s.end_line,
         (s.end_line - s.line + 1) as line_count
  FROM symbols s
  JOIN files f ON s.file_id = f.id
  WHERE s.kind IN ('function', 'method')
    AND s.end_line IS NOT NULL
    AND (s.end_line - s.line + 1) > 30
  ORDER BY line_count DESC
" 2>/dev/null | while IFS='|' read -r filepath name kind start_line end_line line_count; do
  # Check nesting: >4 levels ~ indent >16 spaces (4 spaces per level)
  if [ -f "${PROJECT}/${filepath}" ]; then
    MAX_INDENT=$(sed -n "${start_line},${end_line}p" "${PROJECT}/${filepath}" 2>/dev/null \
      | grep -v '^\s*$' \
      | sed 's/[^ \t].*//' \
      | awk '{ gsub(/\t/, "    "); print length }' \
      | sort -rn \
      | head -1)
    if [ -n "$MAX_INDENT" ] && [ "$MAX_INDENT" -gt 16 ]; then
      echo "  ${filepath}:${start_line} — ${kind} ${name} (${line_count} lines, indent ${MAX_INDENT})"
    fi
  fi
done)

if [ -z "$HIGH_RISK_OUTPUT" ]; then
  echo "  None found"
else
  echo "$HIGH_RISK_OUTPUT"
fi
