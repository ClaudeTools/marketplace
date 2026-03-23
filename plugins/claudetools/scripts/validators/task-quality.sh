#!/bin/bash
# Validator: task quality gate — stubs, type abuse, UI verification, typecheck, tests, debug workflow
# SHARED: used by task-completion-gate.sh AND session-stop-dispatcher.sh AND TeammateIdle
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = pass, 1 = soft warnings, 2 = block (hard violations)

validate_task_quality() {
  # Prevent infinite loops — if this is a re-evaluation after blocking, allow stop
  local STOP_HOOK_ACTIVE
  STOP_HOOK_ACTIVE=$(hook_get_field '.stop_hook_active')
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    return 0
  fi

  # On Stop event, skip heavy checks (typecheck, tests) — session-stop-gate handles Stop
  local HOOK_EVENT
  HOOK_EVENT=$(hook_get_field '.hook_event_name')
  if [ "$HOOK_EVENT" = "Stop" ]; then
    return 0
  fi

  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  # Get changed files (git diff for repos, recent mtime otherwise)
  local CHANGED=""
  if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
    CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
    local UNTRACKED
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
    CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')
  fi

  [ -z "$CHANGED" ] && return 0

  local VIOLATIONS=""
  local VIOLATION_COUNT=0
  local WARNINGS=""

  # --- Track UI file changes for visual verification check ---
  local UI_FILES_CHANGED=0

  while IFS= read -r file; do
    [ "${file:0:1}" != "/" ] && file="$CWD/$file"
    [ -f "$file" ] || continue

    # Check if this is a UI file (*.tsx in app/, components/, pages/, src/app/, src/components/)
    case "$file" in
      */app/*.tsx|*/components/*.tsx|*/pages/*.tsx) UI_FILES_CHANGED=$((UI_FILES_CHANGED + 1)) ;;
    esac

    # Skip non-code
    case "$file" in
      *.test.*|*.spec.*|*.bats|*__tests__*|*__mocks__*) continue ;;
      *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh|*.css|*.svg|*.png|*.log|*.jsonl) continue ;;
    esac

    # Stub patterns
    local COUNT
    COUNT=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}' "$file" 2>/dev/null || true)
    COUNT=${COUNT:-0}
    if [ "$COUNT" -gt 0 ]; then
      VIOLATIONS="${VIOLATIONS}\n$(basename "$file"): ${COUNT} stub/placeholder patterns"
      VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
    fi

    # TypeScript type abuse
    case "$file" in
      *.ts|*.tsx)
        local ANY
        ANY=$(grep -co 'as any\b\|: any\b' "$file" 2>/dev/null || true)
        ANY=${ANY:-0}
        if [ "$ANY" -gt 3 ]; then
          VIOLATIONS="${VIOLATIONS}\n$(basename "$file"): ${ANY} uses of 'any' type"
          VIOLATION_COUNT=$((VIOLATION_COUNT + ANY))
        fi

        # Circumvention: 'as unknown as Type' bypasses type safety same as 'as any'
        local UNKNOWN_AS
        UNKNOWN_AS=$(grep -co 'as unknown as\b' "$file" 2>/dev/null || true)
        UNKNOWN_AS=${UNKNOWN_AS:-0}
        if [ "$UNKNOWN_AS" -gt 2 ]; then
          WARNINGS="${WARNINGS}\n$(basename "$file"): ${UNKNOWN_AS} uses of 'as unknown as' — often used to bypass type checking. Use a type guard or fix the types."
        fi
        ;;
    esac

    # --- fetch() without timeout/signal (warn, not block) ---
    case "$file" in
      *.ts|*.tsx)
        local HAS_FETCH
        HAS_FETCH=$(grep -c 'fetch(' "$file" 2>/dev/null || true)
        HAS_FETCH=${HAS_FETCH:-0}
        if [ "$HAS_FETCH" -gt 0 ]; then
          local HAS_TIMEOUT
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
        local CONSOLE_COUNT
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
    # Show only the first 3 violations — enough to act on without overwhelming
    echo -e "$VIOLATIONS" | head -4 >&2
    local TOTAL_VIOLATIONS
    TOTAL_VIOLATIONS=$(echo -e "$VIOLATIONS" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$TOTAL_VIOLATIONS" -gt 3 ]; then
      echo "  ... and $((TOTAL_VIOLATIONS - 3)) more. Fix these first, then re-check." >&2
    fi
    echo "Replace stubs with real implementations and fix 'any' types — shipping stubs means the next developer inherits broken code. Fix these, verify the fix compiles, then mark the task complete." >&2
    return 2
  fi

  # --- UI visual verification check → reject if UI changed without Chrome verification ---
  if [ "$UI_FILES_CHANGED" -gt 0 ]; then
    local HAS_VISUAL_CHECK
    HAS_VISUAL_CHECK=$(echo "$INPUT" | grep -ciE 'chrome|screenshot|verified in browser|visual.?verif|browser.?test|checked in browser|rendered.?correct' 2>/dev/null || true)
    HAS_VISUAL_CHECK=${HAS_VISUAL_CHECK:-0}
    if [ "$HAS_VISUAL_CHECK" -eq 0 ]; then
      # Check if this is a mechanical refactor (token replacements, class renames, import changes only)
      local IS_MECHANICAL=true
      local UI_DIFF
      UI_DIFF=$(git -C "$CWD" diff -- '*.tsx' '*.jsx' 2>/dev/null | grep '^[+-]' | grep -v '^[+-][+-][+-]' | grep -v '^[+-]$' || true)
      if [ -n "$UI_DIFF" ]; then
        # If any changed line is NOT a className, import, export, or comment change, it's structural
        local STRUCTURAL_LINES
        STRUCTURAL_LINES=$(echo "$UI_DIFF" | grep -vE '^\s*[+-]\s*(className=|import\s|from\s|export\s|//|/\*|\*/)' | grep -v '^[+-][[:space:]]*$' || true)
        if [ -n "$STRUCTURAL_LINES" ]; then
          IS_MECHANICAL=false
        fi
      else
        # No diff available (untracked files) — treat as structural to be safe
        IS_MECHANICAL=false
      fi

      if [ "$IS_MECHANICAL" = true ]; then
        WARNINGS="${WARNINGS}\n${UI_FILES_CHANGED} UI file(s) changed (mechanical refactor detected — token/class replacements only). Visual verification recommended but not required."
      else
        echo "${UI_FILES_CHANGED} UI file(s) changed without visual verification — code that compiles can still render broken in the browser." >&2
        echo "Open the changed pages in Chrome, confirm they render correctly, then mark the task complete." >&2
        return 2
      fi
    fi
  fi

  # --- Typecheck → reject ---
  if [ -f "$CWD/package.json" ]; then
    if grep -q '"typecheck"' "$CWD/package.json" 2>/dev/null; then
      local TC_EXIT=0
      local TC_OUTPUT
      TC_OUTPUT=$(cd "$CWD" && npm run typecheck 2>&1) || TC_EXIT=$?
      if [ "$TC_EXIT" -ne 0 ] || echo "$TC_OUTPUT" | grep -qE 'error TS|Type error'; then
        echo "Typecheck failed — type errors caught here prevent runtime crashes in production. Run 'npm run typecheck', fix the errors, then mark the task complete." >&2
        echo "$TC_OUTPUT" | grep -E 'error TS|Type error' | head -3 >&2
        return 2
      fi
    fi
  fi

  # --- Test suite → reject if tests fail ---
  # Only run tests if changed files are in a testable package
  if [ -n "$CHANGED" ]; then
    local TEST_DIRS=""
    while IFS= read -r file; do
      [ "${file:0:1}" != "/" ] && file="$CWD/$file"
      [ -f "$file" ] || continue
      local DIR
      DIR=$(dirname "$file")
      while [ "$DIR" != "/" ] && [ "$DIR" != "$CWD" ]; do
        if [ -f "$DIR/package.json" ] && grep -q '"test"' "$DIR/package.json" 2>/dev/null; then
          echo "$TEST_DIRS" | grep -qF "$DIR" || TEST_DIRS="${TEST_DIRS}${DIR}\n"
          break
        fi
        DIR=$(dirname "$DIR")
      done
    done <<< "$CHANGED"

    while IFS= read -r tdir; do
      [ -z "$tdir" ] && continue
      local PKG_NAME
      PKG_NAME=$(basename "$tdir")
      local TEST_OUT
      TEST_OUT=$(cd "$tdir" && npm test 2>&1 | tail -10) || true
      if echo "$TEST_OUT" | grep -qE 'FAIL|failed' && ! echo "$TEST_OUT" | grep -qE 'pre-existing|0 failed'; then
        echo "Tests failing in $PKG_NAME — the next developer inherits broken tests and can't trust the suite. Fix them, re-run the suite, then mark the task complete." >&2
        echo "$TEST_OUT" | grep -E 'FAIL|failed' | head -3 >&2
        return 2
      fi
    done < <(echo -e "$TEST_DIRS")
  fi

  # --- Debugging workflow check (bug fix tasks should show evidence of diagnosis) ---
  local TASK_SUBJECT TASK_DESC TASK_TEXT
  TASK_SUBJECT=$(hook_get_field '.task_subject // .subject' || true)
  TASK_DESC=$(hook_get_field '.task_description // .description' || true)
  TASK_TEXT="${TASK_SUBJECT:-} ${TASK_DESC:-}"

  if echo "$TASK_TEXT" | grep -qiE '\b(bug|fix|error|crash|issue|broken|failing)\b'; then
    local EVIDENCE
    EVIDENCE=$(echo "$INPUT" | grep -ciE 'error:|stack.?trace|reproduced|observed|caused by|root cause|logs show|exception|traceback|reproduction' 2>/dev/null || echo 0)
    if [ "$EVIDENCE" -eq 0 ]; then
      echo "Bug fix without diagnostic evidence — guesswork fixes mask the real problem and often introduce new bugs. Reproduce the error first, read logs/traces, then fix based on what you observe." >&2
      return 2
    fi
  fi

  # --- Prevent merge to main without passing all checks ---
  local CURRENT_BRANCH
  CURRENT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "On $CURRENT_BRANCH branch — committing directly to main bypasses code review and risks breaking the build. Create a feature branch first: git checkout -b feat/<description>" >&2
    return 2
  fi

  # --- Soft warnings (exit 1 = injected into conversation, does not block) ---
  if [ -n "$WARNINGS" ]; then
    echo "Suggestions (non-blocking):" >&2
    echo -e "$WARNINGS" >&2
    echo "" >&2
    echo "These won't block completion but are worth addressing." >&2
    return 1
  fi

  return 0
}
