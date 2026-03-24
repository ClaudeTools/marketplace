#!/usr/bin/env bash
# find-queries.sh — Find SQL queries referencing a table and show column usage
# Usage: find-queries.sh <table-name> [project-root]
set -uo pipefail

TABLE="${1:?Usage: find-queries.sh <table-name> [project-root]}"
PROJECT="${2:-$(pwd)}"

echo "=== SQL queries referencing: $TABLE ==="
echo ""

# Find all files with SQL that mentions this table
FILES=$(grep -rl "$TABLE" "$PROJECT" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.sql" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
  2>/dev/null)

if [ -z "$FILES" ]; then
  echo "No SQL queries found referencing '$TABLE'"
  exit 0
fi

# Extract and categorize queries
echo "--- SELECT queries ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -i "SELECT.*$TABLE\|FROM.*$TABLE\|JOIN.*$TABLE" "$f" 2>/dev/null | head -10)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- INSERT/UPDATE/DELETE queries ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -i "INSERT.*$TABLE\|UPDATE.*$TABLE\|DELETE.*$TABLE" "$f" 2>/dev/null | head -10)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- WHERE clauses ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -i "WHERE" "$f" 2>/dev/null | grep -i "$TABLE\|FROM.*$TABLE" | head -10)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- Aggregate functions (SUM/AVG/COUNT) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -iE "(SUM|AVG|COUNT|GROUP BY|HAVING).*" "$f" 2>/dev/null | grep -i "$TABLE" | head -10)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- Schema/DDL ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -iE "(CREATE TABLE|ALTER TABLE|DROP TABLE).*$TABLE" "$f" 2>/dev/null | head -5)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done
