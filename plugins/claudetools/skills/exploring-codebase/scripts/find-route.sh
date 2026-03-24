#!/usr/bin/env bash
# find-route.sh — Trace HTTP route → handler → middleware → DB call chain
# Usage: find-route.sh <route-pattern> [project-root]
# e.g.: find-route.sh "/api/v1/dashboard"
set -uo pipefail

ROUTE="${1:?Usage: find-route.sh <route-pattern> [project-root]}"
PROJECT="${2:-$(pwd)}"
CLI="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/codebase-pilot/dist/cli.js"

echo "=== Tracing route: $ROUTE ==="
echo ""

# Step 1: Find route registration
echo "--- ROUTE REGISTRATION ---"
grep -rn "$ROUTE" "$PROJECT" \
  --include="*.ts" --include="*.js" --include="*.py" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
  2>/dev/null | grep -iE '(get|post|put|delete|patch|route|router|app\.|hono|express|fetch|addEventListener)' | \
  while IFS= read -r match; do
    echo "  $match"
  done

echo ""

# Step 2: Find handler functions
# Extract the handler name from route registration patterns like .get('/path', handlerName)
echo "--- HANDLER FUNCTIONS ---"
HANDLERS=$(grep -rn "$ROUTE" "$PROJECT" \
  --include="*.ts" --include="*.js" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  2>/dev/null | grep -oP '(?:,\s*|=>\s*)(\w+)(?:\s*[,\)])' | grep -oP '\w+' | sort -u)

if [ -n "$HANDLERS" ]; then
  echo "$HANDLERS" | while IFS= read -r handler; do
    echo "  Handler: $handler"
    # Find where this handler is defined
    if [ -f "$CLI" ]; then
      result=$(node "$CLI" find-symbol "$handler" 2>/dev/null | head -5)
      [ -n "$result" ] && echo "$result" | sed 's/^/    /'
    fi
  done
else
  # Fallback: show files containing the route that also have handler-like patterns
  echo "  (Could not extract handler names — showing files with route + handler patterns)"
  grep -rl "$ROUTE" "$PROJECT" \
    --include="*.ts" --include="*.js" \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
    2>/dev/null | while IFS= read -r f; do
    rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "  $rel"
    grep -n "async\|function\|export\|handler\|Controller" "$f" 2>/dev/null | head -5 | sed 's/^/    /'
  done
fi

echo ""

# Step 3: Find middleware in the chain
echo "--- MIDDLEWARE ---"
grep -rn "$ROUTE" "$PROJECT" \
  --include="*.ts" --include="*.js" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  2>/dev/null | grep -oP '(\w+Middleware|\w+Guard|\w+Auth|\w+Check|middleware|use\()' | sort -u | \
  while IFS= read -r mw; do
    echo "  $mw"
  done

echo ""

# Step 4: Find DB calls in handler files
echo "--- DATABASE CALLS ---"
ROUTE_FILES=$(grep -rl "$ROUTE" "$PROJECT" \
  --include="*.ts" --include="*.js" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  2>/dev/null)

if [ -n "$ROUTE_FILES" ]; then
  # Find imports in route files, then check those imported files for DB calls
  echo "$ROUTE_FILES" | while IFS= read -r f; do
    rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    db_calls=$(grep -n 'sql\|query\|prepare\|SELECT\|INSERT\|UPDATE\|DELETE\|findMany\|findFirst\|prisma\|\.db\|getOrgDB\|env\.DB\|D1\|DO\b' "$f" 2>/dev/null | head -10)
    [ -n "$db_calls" ] && echo "  $rel:" && echo "$db_calls" | sed 's/^/    /'
  done
fi
