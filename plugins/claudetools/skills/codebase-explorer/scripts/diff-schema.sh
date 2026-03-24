#!/usr/bin/env bash
# diff-schema.sh — Compare type/schema definitions across two files
# Usage: diff-schema.sh <file1> <file2> [project-root]
# Supports: SQL DDL, TypeScript/JS interfaces, Python dataclasses/pydantic, Go structs,
#           Rust structs, Prisma models, GraphQL types, Protobuf messages, JSON Schema, Zod schemas
set -uo pipefail

FILE1="${1:?Usage: diff-schema.sh <file1> <file2>}"
FILE2="${2:?Usage: diff-schema.sh <file1> <file2>}"
PROJECT="${3:-$(pwd)}"

[[ "$FILE1" != /* ]] && FILE1="$PROJECT/$FILE1"
[[ "$FILE2" != /* ]] && FILE2="$PROJECT/$FILE2"

if [ ! -f "$FILE1" ]; then echo "File not found: $FILE1"; exit 1; fi
if [ ! -f "$FILE2" ]; then echo "File not found: $FILE2"; exit 1; fi

REL1=$(realpath --relative-to="$PROJECT" "$FILE1" 2>/dev/null || basename "$FILE1")
REL2=$(realpath --relative-to="$PROJECT" "$FILE2" 2>/dev/null || basename "$FILE2")

echo "=== Schema Diff: $REL1 vs $REL2 ==="
echo ""

# --- Extractors by file type ---

extract_sql_columns() {
  grep -iP '^\s+\w+\s+(TEXT|INTEGER|REAL|BLOB|VARCHAR|INT|BIGINT|BOOLEAN|TIMESTAMP|DATE|NUMERIC|SERIAL|UUID|JSONB?|FLOAT|DOUBLE|DECIMAL|CHAR|SMALLINT|BYTEA|ARRAY|MONEY|INET|CIDR|MACADDR|POINT|INTERVAL|TIME|ENUM)' "$1" 2>/dev/null | \
    grep -oP '^\s*\K\w+' | sort -u
}

extract_ts_fields() {
  # TypeScript/JS interface, type, class, Zod schema fields
  grep -oP '^\s*\K\w+(?=\s*[?:]|\s*:)' "$1" 2>/dev/null | \
    grep -vE '^(export|import|const|let|var|function|class|interface|type|enum|if|else|for|while|return|async|await|from|default|extends|implements|readonly|static|public|private|protected|abstract|override|declare|module|namespace|require)$' | \
    sort -u
}

extract_python_fields() {
  # Python dataclass fields, pydantic model fields, Django model fields
  grep -oP '^\s+\K\w+(?=\s*[=:]|\s*:\s*\w)' "$1" 2>/dev/null | \
    grep -vE '^(self|cls|def|class|return|if|else|for|while|import|from|pass|raise|try|except|finally|with|as|yield|lambda|assert|True|False|None|and|or|not|in|is|__\w+__)$' | \
    sort -u
}

extract_go_fields() {
  # Go struct fields
  grep -oP '^\s+\K[A-Z]\w*(?=\s+\w)' "$1" 2>/dev/null | sort -u
}

extract_rust_fields() {
  # Rust struct fields
  grep -oP '^\s+\Kpub\s+\K?\w+(?=\s*:)' "$1" 2>/dev/null | sort -u
  grep -oP '^\s+\K\w+(?=\s*:)' "$1" 2>/dev/null | \
    grep -vE '^(pub|fn|let|mut|use|mod|impl|struct|enum|trait|where|type|const|static|extern|unsafe|async|await|self|super|crate)$' | \
    sort -u
}

extract_prisma_fields() {
  # Prisma model fields
  grep -oP '^\s+\K\w+(?=\s+\w)' "$1" 2>/dev/null | \
    grep -vE '^(model|enum|type|generator|datasource|@@|@)' | sort -u
}

extract_graphql_fields() {
  # GraphQL type/input fields
  grep -oP '^\s+\K\w+(?=\s*[(:])' "$1" 2>/dev/null | \
    grep -vE '^(type|input|enum|union|scalar|interface|query|mutation|subscription|schema|directive|extend|fragment)$' | \
    sort -u
}

extract_proto_fields() {
  # Protobuf message fields
  grep -oP '^\s+(optional|required|repeated)?\s*\w+\s+\K\w+(?=\s*=)' "$1" 2>/dev/null | sort -u
}

extract_java_fields() {
  # Java/Kotlin class fields
  grep -oP '^\s+(private|protected|public|val|var)\s+\w+\s+\K\w+' "$1" 2>/dev/null | sort -u
}

extract_json_schema_fields() {
  # JSON Schema properties
  grep -oP '"properties"\s*:\s*\{[^}]*' "$1" 2>/dev/null | grep -oP '"\K\w+(?="\s*:)' | sort -u
}

# --- Detect and extract ---
detect_and_extract() {
  local file="$1"
  local ext="${file##*.}"
  case "$ext" in
    sql)      extract_sql_columns "$file" ;;
    ts|tsx|js|jsx|mjs|cjs) extract_ts_fields "$file" ;;
    py)       extract_python_fields "$file" ;;
    go)       extract_go_fields "$file" ;;
    rs)       extract_rust_fields "$file" ;;
    prisma)   extract_prisma_fields "$file" ;;
    graphql|gql) extract_graphql_fields "$file" ;;
    proto)    extract_proto_fields "$file" ;;
    java|kt)  extract_java_fields "$file" ;;
    json)     extract_json_schema_fields "$file" ;;
    *)
      # Try all extractors, use whichever returns most
      local best="" best_count=0
      for extractor in extract_sql_columns extract_ts_fields extract_python_fields extract_prisma_fields extract_graphql_fields extract_proto_fields; do
        local result count
        result=$($extractor "$file" 2>/dev/null)
        count=$(echo "$result" | grep -c '.' 2>/dev/null || echo 0)
        if [ "$count" -gt "$best_count" ]; then
          best="$result"
          best_count="$count"
        fi
      done
      echo "$best"
      ;;
  esac
}

FIELDS1=$(detect_and_extract "$FILE1")
FIELDS2=$(detect_and_extract "$FILE2")

if [ -z "$FIELDS1" ] && [ -z "$FIELDS2" ]; then
  echo "Could not extract fields from either file."
  echo "Supported formats: SQL, TypeScript/JS, Python, Go, Rust, Prisma, GraphQL, Protobuf, Java/Kotlin, JSON Schema"
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
