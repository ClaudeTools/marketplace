#!/usr/bin/env bash
# diff-schema.sh — Compare type/schema definitions across two files
# Usage: diff-schema.sh <file1> <file2> [project-root]
# Compares column/field names between SQL schemas, TypeScript interfaces, or mixed
set -uo pipefail

FILE1="${1:?Usage: diff-schema.sh <file1> <file2>}"
FILE2="${2:?Usage: diff-schema.sh <file1> <file2>}"
PROJECT="${3:-$(pwd)}"

# Resolve relative paths
[[ "$FILE1" != /* ]] && FILE1="$PROJECT/$FILE1"
[[ "$FILE2" != /* ]] && FILE2="$PROJECT/$FILE2"

if [ ! -f "$FILE1" ]; then echo "File not found: $FILE1"; exit 1; fi
if [ ! -f "$FILE2" ]; then echo "File not found: $FILE2"; exit 1; fi

REL1=$(realpath --relative-to="$PROJECT" "$FILE1" 2>/dev/null || basename "$FILE1")
REL2=$(realpath --relative-to="$PROJECT" "$FILE2" 2>/dev/null || basename "$FILE2")

echo "=== Schema Diff: $REL1 vs $REL2 ==="
echo ""

# Extract field names from TypeScript interfaces/types
extract_ts_fields() {
  local file="$1"
  grep -oP '^\s*\K\w+(?=\s*[?:]|\s*:)' "$file" 2>/dev/null | \
    grep -vE '^(export|import|const|let|var|function|class|interface|type|enum|if|else|for|while|return|async|await|from|default)$' | \
    sort -u
}

# Extract column names from SQL CREATE TABLE
extract_sql_columns() {
  local file="$1"
  grep -iP '^\s+\w+\s+(TEXT|INTEGER|REAL|BLOB|VARCHAR|INT|BIGINT|BOOLEAN|TIMESTAMP|DATE|NUMERIC|SERIAL|UUID)' "$file" 2>/dev/null | \
    grep -oP '^\s*\K\w+' | \
    sort -u
}

# Detect file type and extract fields
extract_fields() {
  local file="$1"
  local ext="${file##*.}"
  case "$ext" in
    sql)  extract_sql_columns "$file" ;;
    ts|tsx|js|jsx) extract_ts_fields "$file" ;;
    *)
      # Try both and use whichever returns more
      local sql_fields ts_fields
      sql_fields=$(extract_sql_columns "$file")
      ts_fields=$(extract_ts_fields "$file")
      sql_count=$(echo "$sql_fields" | grep -c '.' || echo 0)
      ts_count=$(echo "$ts_fields" | grep -c '.' || echo 0)
      if [ "$sql_count" -gt "$ts_count" ]; then
        echo "$sql_fields"
      else
        echo "$ts_fields"
      fi
      ;;
  esac
}

FIELDS1=$(extract_fields "$FILE1")
FIELDS2=$(extract_fields "$FILE2")

if [ -z "$FIELDS1" ] && [ -z "$FIELDS2" ]; then
  echo "Could not extract fields from either file."
  exit 1
fi

# Compare
ONLY_IN_1=$(comm -23 <(echo "$FIELDS1") <(echo "$FIELDS2") 2>/dev/null)
ONLY_IN_2=$(comm -13 <(echo "$FIELDS1") <(echo "$FIELDS2") 2>/dev/null)
IN_BOTH=$(comm -12 <(echo "$FIELDS1") <(echo "$FIELDS2") 2>/dev/null)

MATCH_COUNT=$(echo "$IN_BOTH" | grep -c '.' 2>/dev/null || echo 0)
ONLY1_COUNT=$(echo "$ONLY_IN_1" | grep -c '.' 2>/dev/null || echo 0)
ONLY2_COUNT=$(echo "$ONLY_IN_2" | grep -c '.' 2>/dev/null || echo 0)

echo "Matched: $MATCH_COUNT  |  Only in $REL1: $ONLY1_COUNT  |  Only in $REL2: $ONLY2_COUNT"
echo ""

if [ -n "$ONLY_IN_1" ] && [ "$ONLY1_COUNT" -gt 0 ]; then
  echo "--- Only in $REL1 (missing from $REL2) ---"
  echo "$ONLY_IN_1" | sed 's/^/  - /'
  echo ""
fi

if [ -n "$ONLY_IN_2" ] && [ "$ONLY2_COUNT" -gt 0 ]; then
  echo "--- Only in $REL2 (missing from $REL1) ---"
  echo "$ONLY_IN_2" | sed 's/^/  + /'
  echo ""
fi

if [ -n "$IN_BOTH" ] && [ "$MATCH_COUNT" -gt 0 ]; then
  echo "--- In both ---"
  echo "$IN_BOTH" | sed 's/^/  = /'
fi
