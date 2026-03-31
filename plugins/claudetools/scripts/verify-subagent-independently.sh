#!/bin/bash
# SubagentStop hook — runs INDEPENDENT verification after any subagent completes
# Enforces:
#   - no-shortcuts.md "Never trust a subagent's self-reported passes"
#   - no-shortcuts.md "Assume all prior agent work is broken until verified"
#   - no-shortcuts.md "When inheriting work: read the actual code"
#   - no-shortcuts.md "When an agent reports done: verify yourself"
# Exit 1 = warn (injects independent results into orchestrator), Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null || true)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"' 2>/dev/null || true)

# Skip Explore/Plan agents — they don't produce code changes
case "$AGENT_TYPE" in
  Explore|Plan|plan|explore) exit 0 ;;
esac

# Only run in git repos
git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null || exit 0

# Get files changed by this subagent (recent changes)
CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
ALL_CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')

# If no changes, nothing to verify
[ -z "$ALL_CHANGED" ] && exit 0

ISSUES=""
FILE_COUNT=$(echo "$ALL_CHANGED" | grep -c . 2>/dev/null || echo "0")

# --- 1. Independent typecheck ---
TYPECHECK_RESULT=""
if [ -f "$CWD/package.json" ]; then
  if grep -q '"typecheck"' "$CWD/package.json" 2>/dev/null; then
    TC_OUT=$(cd "$CWD" && npm run typecheck 2>&1 | tail -15) || true
    if echo "$TC_OUT" | grep -qE 'error TS|Error:|FAIL'; then
      TYPECHECK_RESULT="Typecheck failed (fresh run):\n$(echo "$TC_OUT" | grep -E 'error TS|Error:' | head -10)"
      ISSUES="${ISSUES}\n${TYPECHECK_RESULT}"
    fi
  elif [ -f "$CWD/tsconfig.json" ]; then
    TC_OUT=$(cd "$CWD" && npx tsc --noEmit 2>&1 | tail -15) || true
    if echo "$TC_OUT" | grep -qE 'error TS|Error:'; then
      TYPECHECK_RESULT="Typecheck failed (fresh run):\n$(echo "$TC_OUT" | grep -E 'error TS|Error:' | head -10)"
      ISSUES="${ISSUES}\n${TYPECHECK_RESULT}"
    fi
  fi
fi

# --- 2. Independent test run ---
if [ -f "$CWD/package.json" ] && grep -q '"test"' "$CWD/package.json" 2>/dev/null; then
  TEST_OUT=$(cd "$CWD" && timeout 60 npm test 2>&1 | tail -15) || true
  if echo "$TEST_OUT" | grep -qE 'FAIL|failed|ERROR' && ! echo "$TEST_OUT" | grep -qE '0 failed'; then
    ISSUES="${ISSUES}\nTests failed (fresh run):\n$(echo "$TEST_OUT" | grep -E 'FAIL|failed|ERROR' | head -5)"
  fi
fi

# --- 3. Stub check in changed files ---
STUB_FILES=""
while IFS= read -r file; do
  [ "${file:0:1}" != "/" ] && file="$CWD/$file"
  [ -f "$file" ] || continue
  case "$file" in
    *.test.*|*.spec.*|*__tests__*|*__mocks__*|*.md|*.json|*.yaml|*.yml|*.lock|*.sh) continue ;;
  esac
  STUBS=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError' "$file" 2>/dev/null || echo "0")
  [ "$STUBS" -gt 0 ] && STUB_FILES="${STUB_FILES}\n  $(basename "$file"): ${STUBS} stubs"
done <<< "$ALL_CHANGED"

if [ -n "$STUB_FILES" ]; then
  ISSUES="${ISSUES}\nStubs found in changed files:${STUB_FILES}"
fi

# --- Report ---
if [ -n "$ISSUES" ]; then
  HOOK_DECISION="warn" HOOK_REASON="independent verification found issues"
  echo "Subagent (${AGENT_TYPE}) changed ${FILE_COUNT} files. Fresh verification found issues:"
  echo ""
  echo -e "$ISSUES"
  echo ""
  echo "Fix these issues, then review the changed files before proceeding."
  exit 1
fi

# Clean — but still remind orchestrator to verify
echo "Subagent (${AGENT_TYPE}) changed ${FILE_COUNT} files. Typecheck and tests pass." >&2
echo "Review the changed files before proceeding." >&2
exit 0
