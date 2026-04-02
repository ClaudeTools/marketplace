#!/bin/bash
# PreToolUse:Grep — Intercept symbol-like grep queries and redirect to srcpilot.
# Falls back to grep when pilot returns nothing or the DB is unavailable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/hook-input.sh"
source "$SCRIPT_DIR/lib/worktree.sh"
hook_init

# --- Extract tool inputs ---
PATTERN=$(hook_get_field '.tool_input.pattern')
TOOL_PATH=$(hook_get_field '.tool_input.path')
OUTPUT_MODE=$(hook_get_field '.tool_input.output_mode')
GLOB=$(hook_get_field '.tool_input.glob')

# === PASS-THROUGH RULES (exit 0, no stdout — grep runs normally) ===

# 1. No pattern → nothing to redirect
[ -z "$PATTERN" ] && exit 0

# 2. Pattern has regex metacharacters → user wants regex
if echo "$PATTERN" | grep -qP '[[\]\\^$.|?*+{}()]'; then
  exit 0
fi

# 3. Pattern < 4 chars → too ambiguous
[ "${#PATTERN}" -lt 4 ] && exit 0

# 4. Targeting a specific file (path exists and is not a directory) → user knows where to look
if [ -n "$TOOL_PATH" ] && [ -e "$TOOL_PATH" ] && [ ! -d "$TOOL_PATH" ]; then
  exit 0
fi

# 5. Count mode → user wants a number
[ "$OUTPUT_MODE" = "count" ] && exit 0

# 6. Glob targets non-code files → pilot only indexes code
if [ -n "$GLOB" ]; then
  if echo "$GLOB" | grep -qE '\.(md|json|yaml|yml|toml|txt|sh|css|html|svg)$'; then
    exit 0
  fi
fi

# 7. Pattern contains dots (like fs.readFileSync) → qualified identifier, grep handles better
if echo "$PATTERN" | grep -q '\.'; then
  exit 0
fi

# === REDIRECT RULES ===

PILOT_CMD=""

# PascalCase (e.g. MyComponent, UserService)
if echo "$PATTERN" | grep -qE '^[A-Z][a-zA-Z0-9]+$'; then
  PILOT_CMD="find-symbol"
# camelCase (starts lowercase, has at least one uppercase, e.g. getUserById)
elif echo "$PATTERN" | grep -qE '^[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*$'; then
  PILOT_CMD="find-symbol"
# snake_case (lowercase letters/digits with at least one underscore, e.g. user_service)
elif echo "$PATTERN" | grep -qE '^[a-z][a-z0-9_]+$' && echo "$PATTERN" | grep -q '_'; then
  PILOT_CMD="find-symbol"
# Multi-word with spaces (e.g. "parse request body")
elif echo "$PATTERN" | grep -qE '^[a-zA-Z]+ [a-zA-Z ]+$'; then
  PILOT_CMD="navigate"
fi

# No redirect rule matched — allow grep to proceed
[ -z "$PILOT_CMD" ] && exit 0

# === PILOT LOOKUP ===

# Require srcpilot binary and indexed DB
PROJECT_ROOT=$(get_repo_root)
DB_PATH="$PROJECT_ROOT/.srcpilot/db.sqlite"
if ! command -v srcpilot &>/dev/null || [ ! -f "$DB_PATH" ]; then
  exit 0
fi

# Run srcpilot with a hard timeout guard
PILOT_RESULT=$(timeout 4 srcpilot "$PILOT_CMD" "$PATTERN" 2>/dev/null | head -40 | cut -c1-200 || true)

# Fallback: if pilot returns < 2 non-empty lines, allow grep
NON_EMPTY=$(echo "$PILOT_RESULT" | grep -c '\S' || true)
if [ "$NON_EMPTY" -lt 2 ]; then
  exit 0
fi

# Truncate to 2000 chars
TRUNCATED=$(echo "$PILOT_RESULT" | head -c 2000)

# === DENY — inject pilot results ===
jq -n \
  --arg context "srcpilot ($PILOT_CMD) results for \"$PATTERN\":

$TRUNCATED" \
  '{
    hookSpecificOutput: {
      permissionDecision: "deny"
    },
    additionalContext: $context
  }'

exit 0
