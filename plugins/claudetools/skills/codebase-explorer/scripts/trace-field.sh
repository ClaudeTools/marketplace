#!/usr/bin/env bash
# trace-field.sh — Multi-hop field/variable tracing across files
# Usage: trace-field.sh <field-name> [project-root]
# Shows every file that references the field, grouped by role (define/transform/consume)
# Supports: TS/JS, Python, Go, Rust, Java, Ruby, C#, PHP, SQL, Prisma, GraphQL, Protobuf, YAML, TOML, JSON
set -uo pipefail

FIELD="${1:?Usage: trace-field.sh <field-name> [project-root]}"
PROJECT="${2:-$(pwd)}"

# All source/schema/config extensions
INCLUDES=(
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs" --include="*.cjs"
  --include="*.py" --include="*.go" --include="*.rs" --include="*.java" --include="*.kt" --include="*.rb"
  --include="*.cs" --include="*.php" --include="*.swift"
  --include="*.sql" --include="*.prisma" --include="*.graphql" --include="*.gql" --include="*.proto"
  --include="*.json" --include="*.yaml" --include="*.yml" --include="*.toml"
)

EXCLUDES=(
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build
  --exclude-dir=.next --exclude-dir=target --exclude-dir=__pycache__ --exclude-dir=.venv
  --exclude-dir=vendor --exclude-dir=bin --exclude-dir=obj
)

echo "=== Tracing field: $FIELD ==="
echo ""

FILES=$(grep -rl "$FIELD" "$PROJECT" "${INCLUDES[@]}" "${EXCLUDES[@]}" 2>/dev/null | sort)

if [ -z "$FILES" ]; then
  echo "No files reference '$FIELD'"
  exit 0
fi

FILE_COUNT=$(echo "$FILES" | wc -l)
echo "Found in $FILE_COUNT files:"
echo ""

# --- DEFINITIONS: type/interface/struct/schema/model/proto declarations ---
echo "--- DEFINITIONS (where $FIELD is declared/typed) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(interface |type |class |struct |model |enum |message |schema|CREATE TABLE|column|@Column|@Field|field\(|:.*=|def .*:|val |var )' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- TRANSFORMS: mapping/conversion/assignment ---
echo "--- TRANSFORMS (where $FIELD is mapped/converted/assigned) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(=>|map\(|\.map|transform|convert|adapt|normalize|serialize|deserialize|marshal|unmarshal|encode|decode|from_|to_|into\(|as_|\.into|parse)' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- QUERIES: SQL, ORM, Prisma, GraphQL, Drizzle, TypeORM, SQLAlchemy ---
echo "--- QUERIES (database/API references to $FIELD) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(SELECT|WHERE|INSERT|UPDATE|DELETE|SUM|AVG|COUNT|GROUP BY|ORDER BY|sql|query|prepare|bind|findMany|findFirst|findUnique|create\(|update\(|delete\(|filter\(|\.objects\.|\.query\.|\.where\(|\.select\(|\.from\(|Exec|QueryRow|mutation|subscription)' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- DISPLAY: frontend/UI/template rendering ---
echo "--- DISPLAY (frontend/UI/template references to $FIELD) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(render|return.*<|jsx|tsx|display|format|className|style|template|{{|{%|v-bind|:class|@click|<%=|<%= |erb|jinja|mustache|handlebars|\.html)' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- VALIDATION: schema validation, zod, yup, joi, pydantic ---
echo "--- VALIDATION (where $FIELD is validated/constrained) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$FIELD" "$f" 2>/dev/null | grep -iE '(z\.|zod|yup|joi|validator|validate|pydantic|@validates|constraint|check\(|assert|must|required|optional|nullable|min\(|max\(|regex|pattern|Field\()' | head -5)
  [ -n "$matches" ] && echo "  $rel" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- ALL REFERENCES ---
echo "--- ALL REFERENCES (ungrouped) ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  count=$(grep -c "$FIELD" "$f" 2>/dev/null || echo 0)
  echo "  $rel ($count references)"
done
