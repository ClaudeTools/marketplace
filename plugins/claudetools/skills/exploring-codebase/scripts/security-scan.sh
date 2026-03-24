#!/usr/bin/env bash
# security-scan.sh — AST-aware security scanning
# Usage: security-scan.sh [--all] [--json] [project-root]
set -uo pipefail

PROJECT=""
SHOW_ALL=false
JSON_OUT=false

for arg in "$@"; do
  case "$arg" in
    --all)  SHOW_ALL=true ;;
    --json) JSON_OUT=true ;;
    *)      PROJECT="$arg" ;;
  esac
done

PROJECT="${PROJECT:-$(pwd)}"

EXCLUDES=(
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist
  --exclude-dir=build --exclude-dir=.wrangler --exclude-dir=.cache
  --exclude-dir=.claude --exclude-dir=.next --exclude-dir=__pycache__
)

SRC_INCLUDES=(
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx"
  --include="*.mjs" --include="*.cjs" --include="*.py" --include="*.go"
  --include="*.rs" --include="*.java" --include="*.rb" --include="*.php"
)

declare -a CRITICAL=()
declare -a HIGH=()
declare -a MEDIUM=()
declare -a LOW=()

add_finding() {
  local severity="$1" file="$2" line="$3" rule="$4" detail="$5"
  local entry="${file}:${line} [${rule}] ${detail}"
  case "$severity" in
    CRITICAL) CRITICAL+=("$entry") ;;
    HIGH)     HIGH+=("$entry") ;;
    MEDIUM)   MEDIUM+=("$entry") ;;
    LOW)      LOW+=("$entry") ;;
  esac
}

# 1. Hardcoded secrets — exclude lines with env lookups
while IFS=: read -r file lineno line; do
  # Skip safe patterns (env lookups, config refs, type defs)
  if echo "$line" | grep -qiE 'process\.env|os\.environ|env\.|config\.|getenv|ENV\['; then
    continue
  fi
  add_finding "CRITICAL" "$file" "$lineno" "hardcoded-secret" "Possible hardcoded secret"
done < <(grep -rnE '(key|secret|token|password|api_key|apiKey)\s*[:=]\s*["\x27][^"\x27]{8,}' \
  "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
  --exclude="*.test.*" --exclude="*.spec.*" --exclude="*.lock" --exclude="*.md" 2>/dev/null || true)

# 2. SQL injection — template literals or concatenation in query calls
while IFS=: read -r file lineno line; do
  if echo "$line" | grep -qE '\$\{|` *\+|"\s*\+\s*|'"'"'\s*\+\s*'; then
    # Check it's not using parameterized placeholders
    if ! echo "$line" | grep -qE '\?\s*[,\)]|\$[0-9]+|:param|:\w+'; then
      add_finding "HIGH" "$file" "$lineno" "sql-injection" "Query uses string interpolation instead of parameters"
    fi
  fi
done < <(grep -rnE '\.(prepare|query|exec|raw|execute)\s*\(' \
  "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
  --exclude="*.test.*" --exclude="*.spec.*" 2>/dev/null || true)

# 3. Insecure crypto — MD5/SHA1 in non-test files
while IFS=: read -r file lineno line; do
  add_finding "MEDIUM" "$file" "$lineno" "insecure-crypto" "MD5/SHA1 usage detected"
done < <(grep -rnE '\b(MD5|md5|SHA1|sha1|createHash\s*\(\s*["\x27](md5|sha1))\b' \
  "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
  --exclude="*.test.*" --exclude="*.spec.*" --exclude="*.lock" 2>/dev/null || true)

# 4. Console.log in production source
while IFS=: read -r file lineno line; do
  # Skip test files
  case "$file" in
    *.test.* | *.spec.* | *__tests__*) continue ;;
  esac
  add_finding "LOW" "$file" "$lineno" "console-log" "console.log/debug in source"
done < <(grep -rnE '\bconsole\.(log|debug)\b' \
  "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
  --exclude="*.test.*" --exclude="*.spec.*" 2>/dev/null | head -50 || true)

# 5. Unvalidated redirects
while IFS=: read -r file lineno line; do
  add_finding "MEDIUM" "$file" "$lineno" "open-redirect" "Redirect from request params"
done < <(grep -rnE '(redirect|location)\s*[=(]\s*(req\.|request\.|params\.|query\.)' \
  "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
  --exclude="*.test.*" --exclude="*.spec.*" 2>/dev/null || true)

TOTAL=$(( ${#CRITICAL[@]} + ${#HIGH[@]} + ${#MEDIUM[@]} + ${#LOW[@]} ))

if [ "$JSON_OUT" = true ]; then
  echo "{"
  echo "  \"total\": $TOTAL,"
  printf '  "critical": ['
  for i in "${!CRITICAL[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${CRITICAL[$i]//\"/\\\"}"
  done
  printf '],\n'
  printf '  "high": ['
  for i in "${!HIGH[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${HIGH[$i]//\"/\\\"}"
  done
  printf '],\n'
  printf '  "medium": ['
  for i in "${!MEDIUM[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${MEDIUM[$i]//\"/\\\"}"
  done
  printf '],\n'
  printf '  "low": ['
  for i in "${!LOW[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${LOW[$i]//\"/\\\"}"
  done
  printf ']\n'
  echo "}"
  exit 0
fi

echo "=== Security Scan: $PROJECT ==="
echo ""

if [ "${#CRITICAL[@]}" -gt 0 ]; then
  echo "CRITICAL (${#CRITICAL[@]}):"
  for f in "${CRITICAL[@]}"; do echo "  $f"; done
  echo ""
fi

if [ "${#HIGH[@]}" -gt 0 ]; then
  echo "HIGH (${#HIGH[@]}):"
  for f in "${HIGH[@]}"; do echo "  $f"; done
  echo ""
fi

if [ "$SHOW_ALL" = true ] || [ "${#CRITICAL[@]}" -eq 0 ] && [ "${#HIGH[@]}" -eq 0 ]; then
  if [ "${#MEDIUM[@]}" -gt 0 ]; then
    echo "MEDIUM (${#MEDIUM[@]}):"
    for f in "${MEDIUM[@]}"; do echo "  $f"; done
    echo ""
  fi

  if [ "${#LOW[@]}" -gt 0 ]; then
    echo "LOW (${#LOW[@]}):"
    for f in "${LOW[@]}"; do echo "  $f"; done
    echo ""
  fi
fi

echo "Total findings: $TOTAL (${#CRITICAL[@]} critical, ${#HIGH[@]} high, ${#MEDIUM[@]} medium, ${#LOW[@]} low)"
if [ "$SHOW_ALL" = false ] && [ "${#MEDIUM[@]}" -gt 0 ] || [ "${#LOW[@]}" -gt 0 ]; then
  echo "Use --all to show medium/low severity findings"
fi
