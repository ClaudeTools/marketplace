#!/usr/bin/env bash
# call-chain.sh — bidirectional call chain: callers → function → callees
# Usage: call-chain.sh <function-name> [project-root] [--all] [--json]
set -euo pipefail

FUNC="${1:?Usage: call-chain.sh <function-name> [project-root] [--all] [--json]}"
ROOT="${2:-.}"
SHOW_ALL=false
JSON_MODE=false

for arg in "$@"; do
  case "$arg" in
    --all)  SHOW_ALL=true ;;
    --json) JSON_MODE=true ;;
  esac
done

PAGE_LIMIT=20

EXCLUDES=(
  --exclude-dir=node_modules
  --exclude-dir=.git
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=.next
  --exclude-dir=coverage
  --exclude-dir=.claude
  --exclude-dir=.wrangler
  --exclude-dir=.cache
  --exclude-dir=.turbo
  --binary-files=without-match
)

FILE_TYPES=(
  --include='*.ts' --include='*.tsx'
  --include='*.js' --include='*.jsx'
  --include='*.py'
  --include='*.go'
  --include='*.rs'
  --include='*.rb'
  --include='*.java'
  --include='*.kt'
  --include='*.swift'
)

# Step 1: Find where the function is defined
DEF_PATTERN="\b(function|const|let|var|def|func|fn|pub fn|private|public|protected|static)\s+${FUNC}\b|\b${FUNC}\s*[=(:]"
mapfile -t DEFINITIONS < <(grep -rnEI "${EXCLUDES[@]}" "${FILE_TYPES[@]}" "$DEF_PATTERN" "$ROOT" 2>/dev/null | head -10 || true)

# Step 2: Find callers (files that invoke this function)
CALL_PATTERN="\b${FUNC}\s*\(|\b${FUNC}\s*<"
mapfile -t ALL_REFS < <(grep -rnEI "${EXCLUDES[@]}" "${FILE_TYPES[@]}" "$CALL_PATTERN" "$ROOT" 2>/dev/null || true)

# Separate callers from the definition file
DEF_FILE=""
if [ ${#DEFINITIONS[@]} -gt 0 ]; then
  DEF_FILE=$(echo "${DEFINITIONS[0]}" | cut -d: -f1)
fi

CALLERS=()
for ref in "${ALL_REFS[@]}"; do
  ref_file=$(echo "$ref" | cut -d: -f1)
  # Skip the definition file itself — those are internal calls or the def
  if [ "$ref_file" != "$DEF_FILE" ]; then
    CALLERS+=("$ref")
  fi
done

# Step 3: Find callees (functions called FROM the definition file)
CALLEES=()
if [ -n "$DEF_FILE" ] && [ -f "$DEF_FILE" ]; then
  # Extract function calls from the definition file
  mapfile -t CALLEES < <(grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$DEF_FILE" 2>/dev/null \
    | sed 's/\s*($//' \
    | sort -u \
    | grep -vE "^(if|for|while|switch|catch|return|throw|new|typeof|instanceof|${FUNC})$" \
    || true)
fi

paginate_arr() {
  local -n items=$1
  local count=${#items[@]}
  [ "$count" -eq 0 ] && return
  local limit=$count
  if ! $SHOW_ALL && [ "$count" -gt "$PAGE_LIMIT" ]; then
    limit=$PAGE_LIMIT
  fi
  for ((i=0; i<limit; i++)); do
    echo "  ${items[$i]}"
  done
  if [ "$limit" -lt "$count" ]; then
    echo "  ... $(( count - limit )) more (use --all to show all)"
  fi
}

if $JSON_MODE; then
  arr_to_json() {
    local items=("$@")
    local limit=${#items[@]}
    if ! $SHOW_ALL && [ "$limit" -gt "$PAGE_LIMIT" ]; then
      limit=$PAGE_LIMIT
    fi
    local first=true
    echo -n "["
    for ((i=0; i<limit; i++)); do
      $first || echo -n ","
      first=false
      printf '%s' "${items[$i]}" | jq -Rs .
    done
    echo -n "]"
  }

  jq -n \
    --arg func "$FUNC" \
    --arg def_file "${DEF_FILE:-not found}" \
    --argjson definitions "$(arr_to_json "${DEFINITIONS[@]}")" \
    --argjson callers "$(arr_to_json "${CALLERS[@]}")" \
    --argjson callees "$(arr_to_json "${CALLEES[@]}")" \
    '{function: $func, definition_file: $def_file, definitions: $definitions, callers: $callers, callees: $callees}'
else
  echo "=== Call chain: $FUNC ==="

  echo ""
  echo "── Definition (${#DEFINITIONS[@]}) ──"
  if [ ${#DEFINITIONS[@]} -eq 0 ]; then
    echo "  (not found)"
  else
    paginate_arr DEFINITIONS
  fi

  echo ""
  echo "── Callers (${#CALLERS[@]}) ──"
  if [ ${#CALLERS[@]} -eq 0 ]; then
    echo "  (none found)"
  else
    paginate_arr CALLERS
  fi

  echo ""
  echo "── Callees from ${DEF_FILE:-???} (${#CALLEES[@]}) ──"
  if [ ${#CALLEES[@]} -eq 0 ]; then
    echo "  (none found)"
  else
    paginate_arr CALLEES
  fi
fi
