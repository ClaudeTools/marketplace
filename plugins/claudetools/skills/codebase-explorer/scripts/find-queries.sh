#!/usr/bin/env bash
# find-queries.sh — Find database queries referencing a table/model and show column usage
# Usage: find-queries.sh <table-or-model-name> [project-root]
# Supports: raw SQL, Prisma, Drizzle, TypeORM, Sequelize, SQLAlchemy, ActiveRecord, GORM, Diesel
set -uo pipefail

TABLE="${1:?Usage: find-queries.sh <table-or-model-name> [project-root]}"
PROJECT="${2:-$(pwd)}"

INCLUDES=(
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs"
  --include="*.py" --include="*.go" --include="*.rs" --include="*.java" --include="*.kt"
  --include="*.rb" --include="*.php" --include="*.cs"
  --include="*.sql" --include="*.prisma" --include="*.graphql" --include="*.gql"
)

EXCLUDES=(
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build
  --exclude-dir=.next --exclude-dir=target --exclude-dir=__pycache__ --exclude-dir=.venv
  --exclude-dir=vendor --exclude-dir=bin --exclude-dir=obj --exclude-dir=migrations
)

echo "=== Queries referencing: $TABLE ==="
echo ""

FILES=$(grep -rl "$TABLE" "$PROJECT" "${INCLUDES[@]}" "${EXCLUDES[@]}" 2>/dev/null)

if [ -z "$FILES" ]; then
  echo "No queries found referencing '$TABLE'"
  exit 0
fi

# --- Raw SQL ---
echo "--- RAW SQL ---"
echo ""
echo "  SELECT:"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -i "SELECT.*$TABLE\|FROM.*$TABLE\|JOIN.*$TABLE" "$f" 2>/dev/null | head -10)
  [ -n "$matches" ] && echo "    $rel:" && echo "$matches" | sed 's/^/      /'
done

echo ""
echo "  INSERT/UPDATE/DELETE:"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -i "INSERT.*$TABLE\|UPDATE.*$TABLE\|DELETE.*$TABLE" "$f" 2>/dev/null | head -10)
  [ -n "$matches" ] && echo "    $rel:" && echo "$matches" | sed 's/^/      /'
done

echo ""
echo "  Aggregates (SUM/AVG/COUNT):"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -iE "(SUM|AVG|COUNT|MIN|MAX|GROUP BY|HAVING)" "$f" 2>/dev/null | grep -i "$TABLE" | head -10)
  [ -n "$matches" ] && echo "    $rel:" && echo "$matches" | sed 's/^/      /'
done

echo ""

# --- ORM Queries ---
echo "--- ORM / QUERY BUILDER ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$TABLE" "$f" 2>/dev/null | grep -iE '(findMany|findFirst|findUnique|create\(|update\(|delete\(|upsert|aggregate|groupBy|\.objects\.|\.filter\(|\.exclude\(|\.annotate\(|\.values\(|\.where\(|\.select\(|\.from\(|\.joins\(|\.includes\(|\.find\(|\.find_by|\.all\b|\.count\b|\.sum\(|QueryRow|Exec|Find\(|First\(|Create\(|Save\(|Delete\(|\.insert\(|\.values\(|\.set\(|repository\.|EntityManager|QueryBuilder)' | head -10)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- Schema/DDL ---
echo "--- SCHEMA / DDL / MODEL ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n -iE "(CREATE TABLE|ALTER TABLE|DROP TABLE|model $TABLE|class $TABLE|@Entity|@Table|type $TABLE|schema\.|table\()" "$f" 2>/dev/null | head -5)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done

echo ""

# --- GraphQL ---
echo "--- GRAPHQL ---"
echo "$FILES" | while IFS= read -r f; do
  rel=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
  matches=$(grep -n "$TABLE" "$f" 2>/dev/null | grep -iE '(type |input |query |mutation |subscription |@resolver|@Query|@Mutation|gql)' | head -5)
  [ -n "$matches" ] && echo "  $rel:" && echo "$matches" | sed 's/^/    /'
done
