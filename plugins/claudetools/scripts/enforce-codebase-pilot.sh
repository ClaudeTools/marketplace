#!/bin/bash
# PreToolUse hook for Grep|Bash — redirects symbol-level searches to codebase-pilot index
# When a search term matches a known symbol in .codeindex/db.sqlite, blocks the grep
# and suggests using find_symbol/find_usages MCP tools instead (faster + more precise).
# Exits 0 always. Outputs block JSON only when a symbol match is found.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Require sqlite3
if ! command -v sqlite3 >/dev/null 2>&1; then
  exit 0
fi

# Find .codeindex/db.sqlite by walking up from CWD
DB_PATH=""
DIR="$(pwd)"
while [ "$DIR" != "/" ]; do
  if [ -f "$DIR/.codeindex/db.sqlite" ]; then
    DB_PATH="$DIR/.codeindex/db.sqlite"
    break
  fi
  DIR=$(dirname "$DIR")
done

[ -z "$DB_PATH" ] && exit 0

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
SEARCH_TERM=""
SUGGESTION="find_symbol"

case "$TOOL_NAME" in
  Grep)
    RAW_PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null || true)
    [ -z "$RAW_PATTERN" ] && exit 0

    # Detect import/require patterns → suggest find_usages
    if echo "$RAW_PATTERN" | grep -qiE '^(import|from|require)\b'; then
      SEARCH_TERM=$(echo "$RAW_PATTERN" | grep -oE '[A-Za-z_][A-Za-z0-9_]{2,}' | tail -1 || true)
      SUGGESTION="find_usages"
    # Detect definition searches → suggest find_symbol
    elif echo "$RAW_PATTERN" | grep -qiE '^(function|class|interface|type|enum|const|let|var|def|export)\b'; then
      SEARCH_TERM=$(echo "$RAW_PATTERN" | grep -oE '[A-Za-z_][A-Za-z0-9_]{2,}' | tail -1 || true)
    # Plain identifier with no regex metacharacters → could be a symbol
    elif echo "$RAW_PATTERN" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
      SEARCH_TERM="$RAW_PATTERN"
    fi
    ;;

  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    [ -z "$CMD" ] && exit 0

    # Only intercept grep/rg/ag commands
    echo "$CMD" | grep -qE '\b(grep|rg|ag)\b' || exit 0

    # Extract quoted search term: grep "term" or rg 'term'
    SEARCH_TERM=$(echo "$CMD" | grep -oE "[\"\'][A-Za-z_][A-Za-z0-9_]*[\"\']" | head -1 | tr -d "\"'" || true)

    # Detect import patterns in the command
    if [ -n "$SEARCH_TERM" ] && echo "$CMD" | grep -qiE 'import|from|require'; then
      SUGGESTION="find_usages"
    fi
    ;;

  *)
    exit 0
    ;;
esac

# Validate: must be a valid identifier, at least 3 chars
[ -z "$SEARCH_TERM" ] && exit 0
[ ${#SEARCH_TERM} -lt 3 ] && exit 0
echo "$SEARCH_TERM" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || exit 0

# Query the index for exact symbol match
SAFE_TERM="${SEARCH_TERM//\'/\'\'}"
MATCHES=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT s.name, s.kind, f.path, s.line
   FROM symbols s JOIN files f ON s.file_id = f.id
   WHERE s.name = '$SAFE_TERM'
   LIMIT 10" 2>/dev/null || true)

[ -z "$MATCHES" ] && exit 0

# Too many matches = overly generic term, let grep handle it
MATCH_COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
[ "$MATCH_COUNT" -gt 8 ] && exit 0

# Build match list for the redirect message
MATCH_LIST=$(echo "$MATCHES" | head -5 | while IFS='|' read -r name kind path line; do
  echo "  - $kind '$name' in $path:$line"
done)

REASON="Codebase index hit: '$SEARCH_TERM' is a known symbol ($MATCH_COUNT match(es)).

Use MCP tool \`$SUGGESTION\` instead — returns exact locations with signatures and relationships.

Index matches:
$MATCH_LIST
Call: $SUGGESTION(name: \"$SEARCH_TERM\")"

HOOK_DECISION="block"
HOOK_REASON="redirect to $SUGGESTION for '$SEARCH_TERM'"

jq -n --arg reason "$REASON" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": $reason
    }
  }'

exit 0
