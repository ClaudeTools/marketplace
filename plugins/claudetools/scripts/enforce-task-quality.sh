#!/bin/bash
# TaskCompleted + TeammateIdle hook — prevents task completion or idle with violations
# Exit 2 = reject completion / keep working (stderr fed back as instructions)
# Exit 0 = allow completion / allow idle

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"

# Prevent infinite loops — if this is a re-evaluation after blocking, allow stop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null || true)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  hook_log "stop_hook_active=true, allowing stop"
  exit 0
fi
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# On Stop event, skip heavy checks (typecheck, tests) — session-stop-gate handles Stop
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
if [ "$HOOK_EVENT" = "Stop" ]; then
  hook_log "Stop event — skipping heavy checks (handled by session-stop-gate)"
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# Get changed files (git diff for repos, recent mtime otherwise)
CHANGED=""
if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
  CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
  UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
  CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')
fi

[ -z "$CHANGED" ] && exit 0

VIOLATIONS=""
VIOLATION_COUNT=0
WARNINGS=""

# --- Track UI file changes for visual verification check ---
UI_FILES_CHANGED=0

while IFS= read -r file; do
  [ "${file:0:1}" != "/" ] && file="$CWD/$file"
  [ -f "$file" ] || continue

  # Check if this is a UI file (*.tsx in app/, components/, pages/, src/app/, src/components/)
  case "$file" in
    */app/*.tsx|*/components/*.tsx|*/pages/*.tsx) UI_FILES_CHANGED=$((UI_FILES_CHANGED + 1)) ;;
  esac

  # Skip non-code
  case "$file" in
    *.test.*|*.spec.*|*__tests__*|*__mocks__*) continue ;;
    *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh|*.css|*.svg|*.png|*.log|*.jsonl) continue ;;
  esac

  # Stub patterns
  COUNT=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}' "$file" 2>/dev/null || true)
  COUNT=${COUNT:-0}
  if [ "$COUNT" -gt 0 ]; then
    VIOLATIONS="${VIOLATIONS}\n$(basename "$file"): ${COUNT} stub/placeholder patterns"
    VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
  fi

  # TypeScript type abuse
  case "$file" in
    *.ts|*.tsx)
      ANY=$(grep -co 'as any\b\|: any\b' "$file" 2>/dev/null || true)
      ANY=${ANY:-0}
      if [ "$ANY" -gt 3 ]; then
        VIOLATIONS="${VIOLATIONS}\n$(basename "$file"): ${ANY} uses of 'any' type"
        VIOLATION_COUNT=$((VIOLATION_COUNT + ANY))
      fi
      ;;
  esac

  # --- fetch() without timeout/signal (warn, not block) ---
  case "$file" in
    *.ts|*.tsx)
      HAS_FETCH=$(grep -c 'fetch(' "$file" 2>/dev/null || true)
      HAS_FETCH=${HAS_FETCH:-0}
      if [ "$HAS_FETCH" -gt 0 ]; then
        HAS_TIMEOUT=$(grep -cE 'AbortController|signal:|timeout:|AbortSignal\.timeout' "$file" 2>/dev/null || true)
        HAS_TIMEOUT=${HAS_TIMEOUT:-0}
        if [ "$HAS_TIMEOUT" -eq 0 ]; then
          WARNINGS="${WARNINGS}\n$(basename "$file"): ${HAS_FETCH} fetch() calls without timeout/AbortController — consider adding timeouts"
        fi
      fi
      ;;
  esac

  # --- console.log in production code (warn, not block) ---
  case "$file" in
    *.ts|*.tsx)
      CONSOLE_COUNT=$(grep -cE 'console\.(log|debug)\(' "$file" 2>/dev/null || true)
      CONSOLE_COUNT=${CONSOLE_COUNT:-0}
      if [ "$CONSOLE_COUNT" -gt 0 ]; then
        WARNINGS="${WARNINGS}\n$(basename "$file"): ${CONSOLE_COUNT} console.log/debug calls — use structured logger in production"
      fi
      ;;
  esac
done <<< "$CHANGED"

# --- Hard violations: stubs, type abuse → reject ---
if [ "$VIOLATION_COUNT" -gt 0 ]; then
  echo "${VIOLATION_COUNT} quality issue(s) found:" >&2
  echo -e "$VIOLATIONS" >&2
  echo "" >&2
  echo "Why: Stubs, type abuse, and mocks in production code indicate incomplete work." >&2
  echo "What to do: Replace stubs with real implementations, fix 'any' types with proper types, remove mocks from non-test files. Then mark the task complete again." >&2
HOOK_DECISION="reject"; HOOK_REASON="quality gate failed"
  exit 2
fi

# --- UI visual verification check → reject if UI changed without Chrome verification ---
if [ "$UI_FILES_CHANGED" -gt 0 ]; then
  # Check if the agent's output mentions visual verification
  HAS_VISUAL_CHECK=$(echo "$INPUT" | grep -ciE 'chrome|screenshot|verified in browser|visual.?verif|browser.?test|checked in browser|rendered.?correct' 2>/dev/null || true)
  HAS_VISUAL_CHECK=${HAS_VISUAL_CHECK:-0}
  if [ "$HAS_VISUAL_CHECK" -eq 0 ]; then
    echo "${UI_FILES_CHANGED} UI files (.tsx) changed but no visual verification detected." >&2
    echo "UI changes that aren't verified in a browser often have layout or rendering issues that are invisible in code." >&2
    echo "Open the changed pages in Chrome, confirm they render correctly, then complete the task." >&2
    exit 2
  fi
fi

# --- Typecheck → reject ---
if [ -f "$CWD/package.json" ]; then
  if grep -q '"typecheck"' "$CWD/package.json" 2>/dev/null; then
    TC_EXIT=0
    TC_OUTPUT=$(cd "$CWD" && npm run typecheck 2>&1) || TC_EXIT=$?
    if [ "$TC_EXIT" -ne 0 ] || echo "$TC_OUTPUT" | grep -qE 'error TS|Type error'; then
      echo "Typecheck errors found." >&2
      echo "Why: Type errors on disk are real errors — they cause runtime failures and block CI." >&2
      echo "What to do: Run 'npm run typecheck' to see all errors, fix them, then complete." >&2
      echo "$TC_OUTPUT" | tail -10 >&2
      exit 2
    fi
  fi
fi

# --- Test suite → reject if tests fail ---
# Only run tests if changed files are in a testable package
# For monorepos: find the nearest package.json to the changed files and test there
if [ -n "$CHANGED" ]; then
  # Find unique package directories containing changed files
  TEST_DIRS=""
  while IFS= read -r file; do
    [ "${file:0:1}" != "/" ] && file="$CWD/$file"
    [ -f "$file" ] || continue
    # Walk up to find nearest package.json with a test script
    DIR=$(dirname "$file")
    while [ "$DIR" != "/" ] && [ "$DIR" != "$CWD" ]; do
      if [ -f "$DIR/package.json" ] && grep -q '"test"' "$DIR/package.json" 2>/dev/null; then
        # Only add if not already in list
        echo "$TEST_DIRS" | grep -qF "$DIR" || TEST_DIRS="${TEST_DIRS}${DIR}\n"
        break
      fi
      DIR=$(dirname "$DIR")
    done
  done <<< "$CHANGED"

  # Run tests in each affected package (not the monorepo root)
  while IFS= read -r tdir; do
    [ -z "$tdir" ] && continue
    PKG_NAME=$(basename "$tdir")
    TEST_OUT=$(cd "$tdir" && npm test 2>&1 | tail -10) || true
    if echo "$TEST_OUT" | grep -qE 'FAIL|failed' && ! echo "$TEST_OUT" | grep -qE 'pre-existing|0 failed'; then
      echo "Tests failing in $PKG_NAME." >&2
      echo "$TEST_OUT" | grep -E 'FAIL|failed' | head -5 >&2
      echo "" >&2
      echo "Fix failing tests before completing the task." >&2
      HOOK_DECISION="reject"; HOOK_REASON="tests failing in $PKG_NAME"
      exit 2
    fi
  done < <(echo -e "$TEST_DIRS")
fi

# --- Debugging workflow check (bug fix tasks should show evidence of diagnosis) ---
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // .subject // ""' 2>/dev/null || true)
TASK_DESC=$(echo "$INPUT" | jq -r '.task_description // .description // ""' 2>/dev/null || true)
TASK_TEXT="${TASK_SUBJECT} ${TASK_DESC}"

if echo "$TASK_TEXT" | grep -qiE '\b(bug|fix|error|crash|issue|broken|failing)\b'; then
  # Bug fix task — check for evidence of REPRODUCE→OBSERVE→FIX workflow
  EVIDENCE=$(echo "$INPUT" | grep -ciE 'error:|stack.?trace|reproduced|observed|caused by|root cause|logs show|exception|traceback|reproduction' 2>/dev/null || echo 0)
  if [ "$EVIDENCE" -eq 0 ]; then
    echo "Bug fix task detected but no diagnostic evidence found." >&2
    echo "Follow the REPRODUCE → OBSERVE → HYPOTHESIZE → FIX workflow:" >&2
    echo "  1. Reproduce the error and capture the output" >&2
    echo "  2. Read logs/stack traces to observe what happened" >&2
    echo "  3. Form a hypothesis about the root cause" >&2
    echo "  4. Fix based on evidence, not guesswork" >&2
    HOOK_DECISION="reject"; HOOK_REASON="bug fix without diagnostic evidence"
    exit 2
  fi
fi

# --- Prevent merge to main without passing all checks ---
CURRENT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "You are on the main branch." >&2
  echo "Working directly on main skips code review and can break the build for all users." >&2
  echo "Create a feature branch first: git checkout -b feat/<description>" >&2
  HOOK_DECISION="reject"; HOOK_REASON="working on main branch"
  exit 2
fi

# --- Soft warnings (exit 1 = injected into conversation, does not block) ---
if [ -n "$WARNINGS" ]; then
  echo "Suggestions (non-blocking):" >&2
  echo -e "$WARNINGS" >&2
  echo "" >&2
  echo "These won't block completion but are worth addressing." >&2
  exit 1
fi

exit 0

hook_log_result 0 "allow" "no violations"
