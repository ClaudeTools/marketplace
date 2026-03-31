#!/bin/bash
# Validator: task quality gate — stubs, type abuse, UI verification, typecheck, tests, debug workflow
# SHARED: used by task-completion-gate.sh AND session-stop-dispatcher.sh AND TeammateIdle
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = pass, 1 = soft warnings, 2 = block (hard violations)

validate_task_quality() {
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/code-quality.sh"

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
    is_test_file "$file" && continue
    case "$file" in
      *.bats) continue ;;
      *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh|*.css|*.svg|*.png|*.log|*.jsonl) continue ;;
    esac

    # Stub patterns
    local COUNT
    COUNT=$(count_stubs_in_file "$file")
    if [ "$COUNT" -gt 0 ]; then
      VIOLATIONS="${VIOLATIONS}\n$(basename "$file"): ${COUNT} stub/placeholder patterns"
      VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
    fi

    # TypeScript type abuse
    case "$file" in
      *.ts|*.tsx)
        local ANY
        ANY=$(count_type_abuse "$file")
        if [ "$ANY" -gt 3 ]; then
          WARNINGS="${WARNINGS}\n$(basename "$file"): ${ANY} uses of 'any' type — prefer explicit types over 'any'"
        fi

        # Circumvention: 'as unknown as Type' bypasses type safety same as 'as any'
        local UNKNOWN_AS
        UNKNOWN_AS=$(count_unknown_as "$file")
        if [ "$UNKNOWN_AS" -gt 2 ]; then
          WARNINGS="${WARNINGS}\n$(basename "$file"): ${UNKNOWN_AS} uses of 'as unknown as' — often used to bypass type checking. Use a type guard or fix the types."
        fi

        local TS_IGNORES
        TS_IGNORES=$(count_ts_ignores "$file")
        if [ "$TS_IGNORES" -gt 1 ]; then
          WARNINGS="${WARNINGS}\n$(basename "$file"): ${TS_IGNORES} @ts-ignore/@ts-expect-error directives"
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
    echo "Replace stubs with real implementations — shipping stubs means the next developer inherits broken code. Fix these, verify the fix compiles, then mark the task complete." >&2
    return 2
  fi

  # --- UI visual verification check → reject if UI changed without Chrome verification ---
  if [ "$UI_FILES_CHANGED" -gt 0 ]; then
    # First, check if ALL changed UI files are data-only (no visual impact).
    # Data-only patterns: type/interface definitions, props, API response mapping,
    # hooks (use*), config objects, re-exports — none affect rendered layout.
    local VISUAL_FILES=0
    while IFS= read -r file; do
      [ "${file:0:1}" != "/" ] && file="$CWD/$file"
      [ -f "$file" ] || continue
      case "$file" in
        */app/*.tsx|*/components/*.tsx|*/pages/*.tsx) ;;
        *) continue ;;
      esac
      # Get the diff for this specific file
      local FILE_DIFF
      FILE_DIFF=$(git -C "$CWD" diff -- "$file" 2>/dev/null | grep '^[+-]' | grep -v '^[+-][+-][+-]' | grep -v '^[+-]$' || true)
      if [ -z "$FILE_DIFF" ]; then
        # Untracked file — check file content directly for visual indicators
        if grep -qE '<[A-Z][a-zA-Z]*[\s/>]|className=|style=|<div|<span|<section|<header|<footer|<main|<form|<button|<input|<table|<ul|<ol|<li|<img|<svg|return\s*\(' "$file" 2>/dev/null; then
          # Has JSX/HTML rendering — check if it's more than just types
          if grep -qE 'className=|style=|<div|<span|<section|<header|<footer|<main|<form|<button|<input|<table|<ul|<ol|<li|<img|<svg|css|tailwind' "$file" 2>/dev/null; then
            VISUAL_FILES=$((VISUAL_FILES + 1))
          fi
        fi
        continue
      fi
      # Filter out data-only lines: types, interfaces, imports, exports, comments,
      # props/type annotations, API mapping, hook calls, const/let/var declarations
      # without JSX, and pure whitespace changes
      local VISUAL_LINES
      VISUAL_LINES=$(echo "$FILE_DIFF" | grep -vE '^\s*[+-]\s*(//|/\*|\*/|\*\s|import\s|from\s|export\s(type|interface|default)|type\s+[A-Z]|interface\s+[A-Z]|^\s*\}|^\s*\{|props\.|Props|\.map\(|\.filter\(|\.find\(|\.reduce\(|\.forEach\(|async\s|await\s|return\s+[a-z]|const\s+\w+\s*[:=]|let\s+\w+\s*[:=]|function\s|use[A-Z]\w*\(|fetch\(|\.json\(|\.then\(|\.catch\(|throw\s|try\s*\{|catch\s*\(|console\.|:\s*(string|number|boolean|null|undefined|void|any|Record|Array|Promise|Partial|Required|Pick|Omit))' | grep -v '^[+-][[:space:]]*$' || true)
      # Check if remaining lines contain visual indicators (JSX elements, className, style, CSS)
      if [ -n "$VISUAL_LINES" ]; then
        if echo "$VISUAL_LINES" | grep -qE 'className=|style=|<[A-Za-z]+[\s/>]|css|tailwind|px-|py-|mx-|my-|flex|grid|gap-|text-|bg-|border|rounded|shadow|w-|h-|<div|<span|<section|<header|<p>' 2>/dev/null; then
          VISUAL_FILES=$((VISUAL_FILES + 1))
        fi
      fi
    done <<< "$CHANGED"

    # If no files have visual changes, skip visual verification entirely
    if [ "$VISUAL_FILES" -eq 0 ]; then
      : # Data-only changes to UI files — no visual verification needed
    else
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
          WARNINGS="${WARNINGS}\n${VISUAL_FILES} UI file(s) changed (mechanical refactor detected — token/class replacements only). Visual verification recommended but not required."
        else
          WARNINGS="${WARNINGS}\n${VISUAL_FILES} UI file(s) changed without visual verification — open changed pages in Chrome to confirm rendering."
        fi
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
        WARNINGS="${WARNINGS}\n$PKG_NAME: Tests failing — fix them before shipping"
        WARNINGS="${WARNINGS}\n$(echo "$TEST_OUT" | grep -E 'FAIL|failed' | head -3)"
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
    EVIDENCE=$(echo "$INPUT" | grep -ciE 'error:|stack.?trace|reproduced|observed|caused by|root cause|logs show|exception|traceback|reproduction' 2>/dev/null || true)
    EVIDENCE=$(echo "$EVIDENCE" | tr -d '[:space:]')
    EVIDENCE="${EVIDENCE:-0}"
    if [ "$EVIDENCE" -eq 0 ]; then
      WARNINGS="${WARNINGS}\nBug fix without diagnostic evidence — reproduce the error first, read logs/traces"
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
