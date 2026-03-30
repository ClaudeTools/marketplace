#!/bin/bash
# Validator: deterministic post-agent output audit
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = clean, 1 = violations found (warning)

validate_agent_output() {
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/code-quality.sh"

  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  # Find files modified in the last 5 minutes (covers typical agent run duration)
  # Fall back to git diff if in a repo
  local CHANGED_FILES=""
  if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
    CHANGED_FILES=$(git -C "$CWD" diff --name-only HEAD 2>/dev/null || true)
    # Also include untracked files
    local UNTRACKED
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
    CHANGED_FILES=$(printf '%s\n%s' "$CHANGED_FILES" "$UNTRACKED" | sort -u | sed '/^$/d')
  else
    CHANGED_FILES=$(find "$CWD" -maxdepth 4 -type f -mmin -5 -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' 2>/dev/null || true)
  fi

  if [ -z "$CHANGED_FILES" ]; then
    return 0
  fi

  local ISSUES=""
  local FILES_CHECKED=0
  local FILES_WITH_ISSUES=0
  local SCOPE_WARNINGS=""

  # --- Scope check: count total changed files ---
  local FILE_COUNT
  FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
  if [ "$FILE_COUNT" -gt 15 ]; then
    SCOPE_WARNINGS="${SCOPE_WARNINGS}\nLARGE CHANGE SET: ${FILE_COUNT} files changed. Verify scope matches the original request. Agents tend to over-modify."
  fi

  # --- Check for new dependencies in package.json ---
  if echo "$CHANGED_FILES" | grep -q 'package.json'; then
    local PKG_ADDITIONS
    PKG_ADDITIONS=$(git -C "$CWD" diff HEAD -- '*/package.json' 'package.json' 2>/dev/null | grep '^+' | grep -v '^+++' | grep '".*":.*"[0-9^~]' || true)
    if [ -n "$PKG_ADDITIONS" ]; then
      local DEP_COUNT
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
    is_test_file "$file" && continue
    case "$file" in
      *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh) continue ;;
      *.config.*|*.rc|.env*|*.css|*.svg|*.png|*.jpg) continue ;;
    esac

    FILES_CHECKED=$((FILES_CHECKED + 1))
    local FILE_ISSUES=""

    # --- Stub/placeholder patterns ---
    local STUBS
    STUBS=$(count_stubs_in_file "$file")
    [ "$STUBS" -gt 0 ] && FILE_ISSUES="${FILE_ISSUES}  - ${STUBS} stub/TODO markers\n"

    # --- TypeScript-specific ---
    case "$file" in
      *.ts|*.tsx)
        local ANY_COUNT
        ANY_COUNT=$(count_type_abuse "$file")
        [ "$ANY_COUNT" -gt 3 ] && FILE_ISSUES="${FILE_ISSUES}  - ${ANY_COUNT} uses of 'any' type\n"

        local TS_IGNORE
        TS_IGNORE=$(count_ts_ignores "$file")
        [ "$TS_IGNORE" -gt 1 ] && FILE_ISSUES="${FILE_ISSUES}  - ${TS_IGNORE} @ts-ignore/@ts-expect-error directives\n"
        ;;
    esac

    # --- Console-only function bodies ---
    local CONSOLE_ONLY
    CONSOLE_ONLY=$(grep -cE 'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*console\.(log|error|warn)\(' "$file" 2>/dev/null || true)
    [ "$CONSOLE_ONLY" -gt 0 ] && FILE_ISSUES="${FILE_ISSUES}  - ${CONSOLE_ONLY} console-only function bodies\n"

    # --- Broken relative imports (only .ts/.tsx files, only relative paths) ---
    case "$file" in
      *.ts|*.tsx)
        local FILE_DIR
        FILE_DIR=$(dirname "$file")
        while IFS= read -r imp; do
          [ -z "$imp" ] && continue
          # Resolve relative to the file's directory
          local RESOLVED="$FILE_DIR/$imp"
          local FOUND=0
          for ext in "" ".ts" ".tsx" ".js" ".jsx"; do
            [ -f "${RESOLVED}${ext}" ] && FOUND=1 && break
          done
          if [ "$FOUND" -eq 0 ]; then
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
      local BASENAME
      BASENAME=$(basename "$file")
      ISSUES="${ISSUES}\n**${BASENAME}:**\n${FILE_ISSUES}"
    fi
  done <<< "$CHANGED_FILES"

  # Typecheck removed — task-completion-gate already runs typecheck at TaskCompleted.
  # Running it here too added ~870ms avg latency to every agent call for duplicate work.

  if [ -n "$ISSUES" ] || [ -n "$SCOPE_WARNINGS" ]; then
    echo "Post-agent review: ${FILES_WITH_ISSUES}/${FILES_CHECKED} files checked (${FILE_COUNT} total changed)"
    if [ -n "$SCOPE_WARNINGS" ]; then
      echo -e "$SCOPE_WARNINGS"
    fi
    if [ -n "$ISSUES" ]; then
      echo -e "$ISSUES"
    fi
    echo "Fix issues before proceeding. Typecheck runs at task completion."
    return 1
  fi

  return 0
}
