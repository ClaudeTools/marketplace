#!/usr/bin/env bash
# trace-field.sh — Multi-hop field/variable tracing across files
# Usage: trace-field.sh <field-name> [project-root]
# Shows every file that references the field, grouped by role (define/transform/consume)
set -uo pipefail

FIELD="${1:?Usage: trace-field.sh <field-name> [project-root]}"
PROJECT="${2:-$(pwd)}"
CLI="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/codebase-pilot/dist/cli.js"

echo "=== Tracing field: $FIELD ==="
echo ""

# Step 1: Find all files containing this field
FILES=$(grep -rl "$FIELD" "$PROJECT" \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.sql" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
  2>/dev/null | sort)

if [ -z "$FILES" ]; then
  echo "No files reference '$FIELD'"
  exit 0
fi

FILE_COUNT=$(echo "$FILES" | wc -l)
echo "Found in $FILE_COUNT files:"
echo ""

# Step 2: Categorize each file's relationship to the field
echo "--- DEFINITIONS (where $FIELD is declared/typed) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  # Look for type/interface/schema definitions
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(interface|type|class|schema|CREATE TABLE|column|:.*=)' | head -3)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- TRANSFORMS (where $FIELD is mapped/converted/assigned) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(=>|map\(|\.${FIELD}\s*=|transform|convert|adapt|normalize)' | head -3)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- QUERIES (SQL/ORM references to $FIELD) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(SELECT|WHERE|INSERT|UPDATE|SUM|AVG|COUNT|GROUP BY|ORDER BY|sql|query|prepare|bind)' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- DISPLAY (frontend/UI references to $FIELD) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(render|return|jsx|tsx|display|format|<|className|style)' | head -3)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""
echo "--- ALL REFERENCES (ungrouped) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  count=$(grep -c "$FIELD" "$f" 2>/dev/null || echo 0)
  echo "  $rel ($count references)"
done
