#!/bin/bash
# PostToolUse hook for Agent — audits all files changed by a subagent
# Runs deterministic checks across the full body of work, not file-by-file
# Exit 1 with report = warning injected into conversation (orchestrator sees it)
# Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# Find files modified in the last 5 minutes (covers typical agent run duration)
# Fall back to git diff if in a repo
CHANGED_FILES=""
if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
  CHANGED_FILES=$(git -C "$CWD" diff --name-only HEAD 2>/dev/null || true)
  # Also include untracked files
  UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
  CHANGED_FILES=$(printf '%s\n%s' "$CHANGED_FILES" "$UNTRACKED" | sort -u | sed '/^$/d')
else
  CHANGED_FILES=$(find "$CWD" -maxdepth 4 -type f -mmin -5 -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' 2>/dev/null || true)
fi

if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

ISSUES=""
FILES_CHECKED=0
FILES_WITH_ISSUES=0
SCOPE_WARNINGS=""

# --- Scope check: count total changed files ---
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -gt 15 ]; then
  SCOPE_WARNINGS="${SCOPE_WARNINGS}\nLARGE CHANGE SET: ${FILE_COUNT} files changed. Verify scope matches the original request. Agents tend to over-modify."
fi

# --- Check for new dependencies in package.json ---
if echo "$CHANGED_FILES" | grep -q 'package.json'; then
  # Look for added dependencies in git diff
  PKG_ADDITIONS=$(git -C "$CWD" diff HEAD -- '*/package.json' 'package.json' 2>/dev/null | grep '^+' | grep -v '^+++' | grep '".*":.*"[0-9^~]' || true)
  if [ -n "$PKG_ADDITIONS" ]; then
    DEP_COUNT=$(echo "$PKG_ADDITIONS" | wc -l | tr -d ' ')
    SCOPE_WARNINGS="${SCOPE_WARNINGS}\nNEW DEPENDENCIES: ${DEP_COUNT} new package(s) added to package.json. Verify these are justified:"
    SCOPE_WARNINGS="${SCOPE_WARNINGS}\n$(echo "$PKG_ADDITIONS" | head -10 | sed 's/^/  /')"
  fi
fi

while IFS= read -r file; do
  # Resolve to absolute path if needed
  [ "${file:0:1}" != "/" ] && file="$CWD/$file"
  [ -f "$file" ] || continue

  # Skip non-code files
  case "$file" in
    *.test.*|*.spec.*|*__tests__*|*__mocks__*) continue ;;
    *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh) continue ;;
    *.config.*|*.rc|.env*|*.css|*.svg|*.png|*.jpg) continue ;;
  esac

  FILES_CHECKED=$((FILES_CHECKED + 1))
  FILE_ISSUES=""

  # --- Stub/placeholder patterns ---
  STUBS=$(grep -ncE 'throw new Error\(.*(not implemented|todo|fixme|placeholder)|//\s*(TODO|FIXME|HACK|STUB|PLACEHOLDER):?\s|NotImplementedError' "$file" 2>/dev/null || true)
  [ "$STUBS" -gt 0 ] && FILE_ISSUES="${FILE_ISSUES}  - ${STUBS} stub/TODO markers\n"

  # --- Empty or hardcoded-return functions ---
  EMPTY=$(grep -cE 'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}|function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*return\s+(null|undefined|\{\}|\[\])' "$file" 2>/dev/null || true)
  [ "$EMPTY" -gt 0 ] && FILE_ISSUES="${FILE_ISSUES}  - ${EMPTY} empty/stub function bodies\n"

  # --- TypeScript-specific ---
  case "$file" in
    *.ts|*.tsx)
      ANY_COUNT=$(grep -co 'as any\b\|: any\b' "$file" 2>/dev/null || true)
      [ "$ANY_COUNT" -gt 3 ] && FILE_ISSUES="${FILE_ISSUES}  - ${ANY_COUNT} uses of 'any' type\n"

      TS_IGNORE=$(grep -cE '@ts-ignore|@ts-expect-error' "$file" 2>/dev/null || true)
      [ "$TS_IGNORE" -gt 1 ] && FILE_ISSUES="${FILE_ISSUES}  - ${TS_IGNORE} @ts-ignore/@ts-expect-error directives\n"
      ;;
  esac

  # --- Console-only function bodies ---
  CONSOLE_ONLY=$(grep -cE 'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*console\.(log|error|warn)\(' "$file" 2>/dev/null || true)
  [ "$CONSOLE_ONLY" -gt 0 ] && FILE_ISSUES="${FILE_ISSUES}  - ${CONSOLE_ONLY} console-only function bodies\n"

  # --- Broken relative imports (only .ts/.tsx files, only relative paths) ---
  case "$file" in
    *.ts|*.tsx)
      FILE_DIR=$(dirname "$file")
      while IFS= read -r imp; do
        [ -z "$imp" ] && continue
        # Resolve relative to the file's directory
        RESOLVED="$FILE_DIR/$imp"
        # Check common extensions: .ts, .tsx, /index.ts, /index.tsx, .js, .jsx
        FOUND=0
        for ext in "" ".ts" ".tsx" ".js" ".jsx"; do
          [ -f "${RESOLVED}${ext}" ] && FOUND=1 && break
        done
        if [ "$FOUND" -eq 0 ]; then
          # Check index file in directory
          for ext in ".ts" ".tsx" ".js" ".jsx"; do
            [ -f "${RESOLVED}/index${ext}" ] && FOUND=1 && break
          done
        fi
        if [ "$FOUND" -eq 0 ]; then
          FILE_ISSUES="${FILE_ISSUES}  - broken import: '$imp' does not resolve\n"
        fi
      done < <(grep -oE "from ['\"](\./[^'\"]+)['\"]" "$file" 2>/dev/null | sed "s/from ['\"]//;s/['\"]$//" || true)
      ;;
  esac

  if [ -n "$FILE_ISSUES" ]; then
    FILES_WITH_ISSUES=$((FILES_WITH_ISSUES + 1))
    BASENAME=$(basename "$file")
    ISSUES="${ISSUES}\n**${BASENAME}:**\n${FILE_ISSUES}"
  fi
done <<< "$CHANGED_FILES"

# --- Independent typecheck (never trust agent's self-reported result) ---
TYPECHECK_FAIL=""
if [ -f "$CWD/package.json" ]; then
  if grep -q '"typecheck"' "$CWD/package.json" 2>/dev/null; then
    TC_OUT=$(cd "$CWD" && npm run typecheck 2>&1 | tail -20) || true
    TC_EXIT=$?
    if [ "$TC_EXIT" -ne 0 ]; then
      TYPECHECK_FAIL="TypeScript typecheck FAILED (independent verification — do not trust agent's claim):\n$(echo "$TC_OUT" | grep -E 'error TS|Error:' | head -10)"
    fi
  elif [ -f "$CWD/tsconfig.json" ]; then
    TC_OUT=$(cd "$CWD" && npx tsc --noEmit 2>&1 | tail -20) || true
    TC_EXIT=$?
    if [ "$TC_EXIT" -ne 0 ]; then
      TYPECHECK_FAIL="TypeScript typecheck FAILED (independent verification — do not trust agent's claim):\n$(echo "$TC_OUT" | grep -E 'error TS|Error:' | head -10)"
    fi
  fi
fi

if [ -n "$ISSUES" ] || [ -n "$TYPECHECK_FAIL" ] || [ -n "$SCOPE_WARNINGS" ]; then
  echo "AGENT AUDIT: ${FILES_WITH_ISSUES}/${FILES_CHECKED} files checked (${FILE_COUNT} total changed)"
  if [ -n "$SCOPE_WARNINGS" ]; then
    echo ""
    echo "Scope warnings:"
    echo -e "$SCOPE_WARNINGS"
  fi
  if [ -n "$ISSUES" ]; then
    echo ""
    echo "Pattern violations found:"
    echo -e "$ISSUES"
  fi
  if [ -n "$TYPECHECK_FAIL" ]; then
    echo ""
    echo -e "$TYPECHECK_FAIL"
  fi
  echo ""
  echo "NEVER trust an agent's self-reported quality gates. This audit ran independently."
  echo "NEVER dismiss diagnostic output as 'stale' or 'transitional' — if the file has errors, it has errors."
  echo "Action: fix all violations, re-run typecheck, verify before proceeding."
  exit 1
fi

exit 0

hook_log_result 0 "allow" "no violations"
