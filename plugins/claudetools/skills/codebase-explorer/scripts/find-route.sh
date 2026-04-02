#!/usr/bin/env bash
# find-route.sh — Trace HTTP route → handler → middleware → DB call chain
# Usage: find-route.sh <route-pattern> [project-root]
# Supports: Express, Hono, Fastify, Next.js, FastAPI, Django, Flask, Gin, Fiber, Rails, Spring, Laravel
set -uo pipefail

ROUTE="${1:?Usage: find-route.sh <route-pattern> [project-root]}"
PROJECT="${2:-$(pwd)}"

INCLUDES=(
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs"
  --include="*.py" --include="*.go" --include="*.rs" --include="*.java" --include="*.kt"
  --include="*.rb" --include="*.php" --include="*.cs" --include="*.swift"
)

EXCLUDES=(
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build
  --exclude-dir=.next --exclude-dir=target --exclude-dir=__pycache__ --exclude-dir=.venv
  --exclude-dir=vendor --exclude-dir=bin --exclude-dir=obj
)

echo "=== Tracing route: $ROUTE ==="
echo ""

# Step 1: Find route registration across frameworks
echo "--- ROUTE REGISTRATION ---"
grep -rn "$ROUTE" "$PROJECT" "${INCLUDES[@]}" "${EXCLUDES[@]}" 2>/dev/null | \
  grep -iE '(get|post|put|delete|patch|options|head|route|router|app\.|hono|express|fastify|fetch|addEventListener|@app\.|@router\.|@Get|@Post|@Put|@Delete|@RequestMapping|@GetMapping|@PostMapping|Route\(|path\(|HandleFunc|r\.GET|r\.POST|group\.|resources |match |Route::)' | \
  head -20 | while IFS= read -r match; do
    echo "  $match"
  done

echo ""

# Step 2: Find handler functions
echo "--- HANDLER FUNCTIONS ---"
HANDLER_FILES=$(grep -rl "$ROUTE" "$PROJECT" "${INCLUDES[@]}" "${EXCLUDES[@]}" 2>/dev/null)

if [ -n "$HANDLER_FILES" ]; then
  echo "$HANDLER_FILES" | while IFS= read -r f; do
    rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    # Show handler-like declarations near the route
    handlers=$(grep -n -A2 "$ROUTE" "$f" 2>/dev/null | grep -iE '(async |function |def |func |fn |public |private |protected |handler|Controller|Action|View|Endpoint|lambda|=>)' | head -5)
    [ -n "$handlers" ] && echo "  $rel:" && echo "$handlers" | sed 's/^/    /'
  done
fi

echo ""

# Step 3: Find middleware in the chain
echo "--- MIDDLEWARE / GUARDS ---"
grep -rn "$ROUTE" "$PROJECT" "${INCLUDES[@]}" "${EXCLUDES[@]}" 2>/dev/null | \
  grep -oP '(\w+[Mm]iddleware|\w+[Gg]uard|\w+[Aa]uth|\w+[Cc]heck|\w+[Pp]olicy|\w+[Ff]ilter|middleware|use\(|@UseGuards|@UseInterceptors|@Middleware|before_action|before_request|depends\()' | \
  sort -u | while IFS= read -r mw; do
    echo "  $mw"
  done

echo ""

# Step 4: Find DB calls in handler files
echo "--- DATABASE CALLS ---"
if [ -n "$HANDLER_FILES" ]; then
  echo "$HANDLER_FILES" | while IFS= read -r f; do
    rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    db_calls=$(grep -n -iE '(sql|query|prepare|SELECT|INSERT|UPDATE|DELETE|findMany|findFirst|findUnique|create\(|\.save|\.destroy|\.objects\.|QueryRow|Exec|\.db\.|getOrgDB|env\.DB|D1|prisma\.|knex|drizzle|sequelize|ActiveRecord|\.where|\.find\(|\.all\b|repository\.|EntityManager|Session\.)' "$f" 2>/dev/null | head -10)
    [ -n "$db_calls" ] && echo "  $rel:" && echo "$db_calls" | sed 's/^/    /'
  done
fi
