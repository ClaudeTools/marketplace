#!/bin/bash
# PreToolUse hook for Grep|Bash — intercepts symbol-level searches and runs
# codebase-pilot CLI directly (no MCP dependency).
#
# When a search term matches a known symbol in .codeindex/db.sqlite, blocks
# the grep and returns results from the index inline. This is faster and more
# precise than grep for symbol lookups.
#
# Exit 0 always. Outputs block JSON with inline results when a symbol match is found.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Find the codebase-pilot CLI
PILOT_CLI="${CLAUDE_PLUGIN_ROOT:-}/codebase-pilot/dist/cli.js"
[ -f "$PILOT_CLI" ] || exit 0

# Find .codeindex/db.sqlite by walking up from CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
DB_PATH=""
PROJECT_ROOT=""
DIR="$CWD"
while [ "$DIR" != "/" ]; do
  if [ -f "$DIR/.codeindex/db.sqlite" ]; then
    DB_PATH="$DIR/.codeindex/db.sqlite"
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

[ -z "$DB_PATH" ] && exit 0

# Require sqlite3 for quick pre-check (avoids slow node startup for non-matches)
if ! command -v sqlite3 >/dev/null 2>&1; then
  exit 0
fi

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
SEARCH_TERM=""
CLI_COMMAND="find-symbol"

case "$TOOL_NAME" in
  Grep)
    RAW_PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null || true)
    [ -z "$RAW_PATTERN" ] && exit 0

    # Detect import/require patterns → use find-usages
    if echo "$RAW_PATTERN" | grep -qiE '^(import|from|require)\b'; then
      SEARCH_TERM=$(echo "$RAW_PATTERN" | grep -oE '[A-Za-z_][A-Za-z0-9_]{2,}' | tail -1 || true)
      CLI_COMMAND="find-usages"
    # Detect definition searches → use find-symbol
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
      CLI_COMMAND="find-usages"
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

# Quick pre-check with sqlite3 (fast) before invoking node (slower)
SAFE_TERM="${SEARCH_TERM//\'/\'\'}"
MATCHES=$(sqlite3 "$DB_PATH" \
  "SELECT COUNT(*) FROM symbols s WHERE s.name = '$SAFE_TERM'" 2>/dev/null || echo "0")

[ "$MATCHES" -eq 0 ] && exit 0
[ "$MATCHES" -gt 8 ] && exit 0  # Too generic, let grep handle it

# Run the CLI directly — get full results inline
RESULT=$(CODEBASE_PILOT_PROJECT_ROOT="$PROJECT_ROOT" \
  node "$PILOT_CLI" "$CLI_COMMAND" "$SEARCH_TERM" 2>/dev/null || true)

[ -z "$RESULT" ] && exit 0

REASON="Codebase index has precise results for '$SEARCH_TERM' ($MATCHES match(es)). Using indexed lookup instead of grep:

$RESULT"

HOOK_DECISION="block"
HOOK_REASON="indexed lookup for '$SEARCH_TERM' via $CLI_COMMAND"

jq -n --arg reason "$REASON" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": $reason
    }
  }'

exit 0
