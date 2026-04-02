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


# --- Pilot-powered checks (structural, requires codebase index) ---
_PILOT_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/scripts/lib/pilot-query.sh"
if [[ -f "$_PILOT_LIB" ]] && [[ -f "${PROJECT}/.srcpilot/db.sqlite" ]]; then
  # shellcheck source=/dev/null
  source "$_PILOT_LIB"
  export SRCPILOT_PROJECT_ROOT="$PROJECT"

  # 6. Dead security validators — exported auth/validate/sanitize functions never imported
  dead_output=$(pilot_dead_code 2>/dev/null || true)
  if [[ -n "$dead_output" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if echo "$line" | grep -qiE '(auth|secur|valid|sanitiz|escap|permission|csrf|xss)'; then
        file=$(echo "$line" | awk '{print $1}')
        add_finding "MEDIUM" "${file:-unknown}" "0" "dead-security-code" "Exported security function never imported: $line"
      fi
    done <<< "$dead_output"
  fi

  # 7. Route files missing auth imports
  # Find files that define routes (app.get/post/put/delete, router.get/post/put/delete)
  while IFS=: read -r route_file _lineno _line; do
    [[ -z "$route_file" ]] && continue
    # Check if this file imports any auth-related symbol
    if ! grep -qiE '(import|require).*\b(auth|middleware|authenticate|authorize|guard|protect|jwt|session)' \
        "$route_file" 2>/dev/null; then
      add_finding "MEDIUM" "$route_file" "0" "missing-auth-middleware" \
        "Route handler file has no auth middleware import"
    fi
  done < <(grep -rlE '\b(app|router)\.(get|post|put|patch|delete)\s*\(' \
    "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
    --exclude="*.test.*" --exclude="*.spec.*" 2>/dev/null | \
    awk '{print $0":0:route"}' || true)

  # 8. Input handler blast radius — find files handling user input and check import graph
  # Locate files that reference req.body / req.params / req.query (user input entry points)
  input_files=$(grep -rlE '\b(req\.(body|params|query)|request\.(body|params|query))\b' \
    "$PROJECT" "${SRC_INCLUDES[@]}" "${EXCLUDES[@]}" \
    --exclude="*.test.*" --exclude="*.spec.*" 2>/dev/null | head -10 || true)
  if [[ -n "$input_files" ]]; then
    while IFS= read -r input_file; do
      [[ -z "$input_file" ]] && continue
      # Use related-files to see how many files depend on this input handler
      rel_path="${input_file#"$PROJECT"/}"
      related=$(pilot_related_files "$rel_path" 2>/dev/null || true)
      affected_count=$(echo "$related" | grep -cE '^\s' || true)
      if [[ "$affected_count" -gt 5 ]]; then
        add_finding "LOW" "$input_file" "0" "high-blast-radius-input" \
          "User-input handler has ${affected_count} related files in import graph"
      fi
    done <<< "$input_files"
  fi
fi

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
