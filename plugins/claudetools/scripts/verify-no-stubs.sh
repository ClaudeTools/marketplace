#!/bin/bash
# PostToolUse hook for Edit|Write — detects stubs, placeholders, and shortcuts
HOOK_DECISION="warn" HOOK_REASON="stubs detected"
# Returns exit 1 with message if banned patterns found (shows warning to user)
# Returns exit 0 if clean

set -euo pipefail

INPUT=$(cat)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Skip if no file path or if it's a non-code file
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Skip test files, config, docs, markdown, json
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__*|*__mocks__*) exit 0 ;;
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock) exit 0 ;;
  *.config.*|*.rc|.env*) exit 0 ;;
  *.sh) exit 0 ;;
  */.claude/hooks/*) exit 0 ;;
esac

ISSUES=""
add() { while IFS= read -r line; do ISSUES="${ISSUES}${line}\n"; done; }

# --- Language-specific stub detection, gated by file extension ---
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx)
    # TypeScript/JavaScript stub throws
    add < <(grep -n -E \
      'throw new Error\(.*(not implemented|todo|fixme|placeholder)' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME/HACK comment markers (JS-style)
    add < <(grep -n -E \
      '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)

    # Empty function bodies
    add < <(grep -n -E \
      '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}' \
      "$FILE_PATH" 2>/dev/null || true)

    # Functions whose body is only console.log/console.error/console.warn (single-line)
    add < <(grep -n -E \
      '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*console\.(log|error|warn)\(.*\);\s*\}' \
      "$FILE_PATH" 2>/dev/null || true)

    # Hardcoded return shortcuts (sole statement in function body, single-line)
    add < <(grep -n -E \
      '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*return\s+(null|undefined|\{\}|\[\])\s*;?\s*\}' \
      "$FILE_PATH" 2>/dev/null || true)

    # Arrow functions with hardcoded return shortcuts
    add < <(grep -n -E \
      '=>\s*(\(\s*)?(null|undefined|\{\}|\[\])(\s*\))?\s*[;,]' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.py)
    # Skip .pyi type stub files — these are legitimate Python type annotations
    case "$FILE_PATH" in *.pyi) exit 0 ;; esac

    # Python stubs
    add < <(grep -n -E \
      'raise\s+NotImplementedError' \
      "$FILE_PATH" 2>/dev/null || true)

    # pass as only function body (line contains only whitespace + pass)
    # Filter out legitimate except/else: pass patterns
    add < <(grep -n -E '^\s*pass\s*$' "$FILE_PATH" 2>/dev/null | while IFS=: read -r lineno rest; do
      # Check if the previous line is an except or else clause
      prev_line=$(sed -n "$((lineno - 1))p" "$FILE_PATH" 2>/dev/null || true)
      if ! echo "$prev_line" | grep -qE '^\s*(except|else)\s*:'; then
        echo "${lineno}:${rest}"
      fi
    done || true)

    # Ellipsis as only function body (line contains only whitespace + ...)
    add < <(grep -n -E \
      '^\s*\.\.\.\s*$' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (Python-style)
    add < <(grep -n -E \
      '#\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.rs)
    # Rust stubs
    add < <(grep -n -E \
      'todo!\(\)|unimplemented!\(\)|panic!\("not implemented"\)' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (Rust-style)
    add < <(grep -n -E \
      '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.go)
    # Go stubs
    add < <(grep -n -E \
      'panic\("not implemented"\)' \
      "$FILE_PATH" 2>/dev/null || true)

    # Functions with only return nil or return ""
    add < <(grep -n -E \
      '^\s*return\s+(nil|"")\s*$' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (Go-style)
    add < <(grep -n -E \
      '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.java)
    # Java stubs
    add < <(grep -n -E \
      'throw new UnsupportedOperationException' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (Java-style)
    add < <(grep -n -E \
      '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.cs)
    # C# stubs
    add < <(grep -n -E \
      'throw new NotImplementedException' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (C#-style)
    add < <(grep -n -E \
      '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;

  *.rb)
    # Ruby stubs
    add < <(grep -n -E \
      'raise\s+NotImplementedError' \
      "$FILE_PATH" 2>/dev/null || true)

    # TODO/FIXME comment markers (Ruby-style)
    add < <(grep -n -E \
      '#\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
      "$FILE_PATH" 2>/dev/null || true)
    ;;
esac

# --- Multi-line stub detection: function body is ONLY return []/{}/ null (across lines) ---
# Uses awk to find functions where the only statement between { and } is a return of empty data
add < <(awk '
  /function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(/ && /{/ {
    fn_start = NR
    fn_line = $0
    brace = 0
    body = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "{") brace++
      if (c == "}") brace--
    }
    if (brace > 0) {
      capturing = 1
      next
    }
  }
  capturing {
    body = body " " $0
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "{") brace++
      if (c == "}") { brace--; if (brace == 0) { capturing = 0 } }
    }
    if (!capturing) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", body)
      gsub(/;/, "", body)
      if (body ~ /^return[[:space:]]+(null|undefined|\{\}|\[\])[[:space:]]*\}$/) {
        print fn_start ": stub function body — only returns empty value"
      }
      if (body ~ /^console\.(log|error|warn)\(.*\)[[:space:]]*\}$/) {
        print fn_start ": console-only function body — no real implementation"
      }
      body = ""
    }
  }
' "$FILE_PATH" 2>/dev/null || true)

# --- Arrow function multi-line: const x = () => { return null/[]/{}; } ---
add < <(awk '
  /=[[:space:]]*\(.*\)[[:space:]]*=>[[:space:]]*\{/ || /=[[:space:]]*\([^)]*$/ {
    fn_start = NR
    fn_line = $0
    brace = 0
    body = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "{") brace++
      if (c == "}") brace--
    }
    if (brace > 0) {
      capturing = 1
      next
    }
  }
  capturing {
    body = body " " $0
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "{") brace++
      if (c == "}") { brace--; if (brace == 0) { capturing = 0 } }
    }
    if (!capturing) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", body)
      gsub(/;/, "", body)
      if (body ~ /^return[[:space:]]+(null|undefined|\{\}|\[\])[[:space:]]*\}$/) {
        print fn_start ": stub arrow function — only returns empty value"
      }
      if (body ~ /^console\.(log|error|warn)\(.*\)[[:space:]]*\}$/) {
        print fn_start ": console-only arrow function — no real implementation"
      }
      body = ""
    }
  }
' "$FILE_PATH" 2>/dev/null || true)

# --- TypeScript-specific checks ---
case "$FILE_PATH" in
  *.ts|*.tsx)
    # ': any' type abuse
    TS_ANY_LIMIT=$(get_threshold "ts_any_limit" "$MODEL_FAMILY")
    TS_ANY_LIMIT=${TS_ANY_LIMIT%.*}
    ANY_COUNT=$({ grep -o ': any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$ANY_COUNT" -gt "$TS_ANY_LIMIT" ]; then
      ISSUES="${ISSUES}WARNING: ${ANY_COUNT} uses of ': any' -- likely type shortcuts\n"
    fi

    # 'as any' cast abuse
    TS_AS_ANY_LIMIT=$(get_threshold "ts_as_any_limit" "$MODEL_FAMILY")
    TS_AS_ANY_LIMIT=${TS_AS_ANY_LIMIT%.*}
    AS_ANY_COUNT=$({ grep -o 'as any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$AS_ANY_COUNT" -gt "$TS_AS_ANY_LIMIT" ]; then
      ISSUES="${ISSUES}WARNING: ${AS_ANY_COUNT} uses of 'as any' -- unsafe type casts\n"
    fi

    # @ts-ignore / @ts-expect-error abuse
    TS_IGNORE_LIMIT=$(get_threshold "ts_ignore_limit" "$MODEL_FAMILY")
    TS_IGNORE_LIMIT=${TS_IGNORE_LIMIT%.*}
    TS_SUPPRESS=$({ grep -oE '@ts-ignore|@ts-expect-error' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$TS_SUPPRESS" -gt "$TS_IGNORE_LIMIT" ]; then
      ISSUES="${ISSUES}WARNING: ${TS_SUPPRESS} uses of @ts-ignore/@ts-expect-error -- suppressing type safety\n"
    fi
    ;;
esac

# Clean up empty lines
ISSUES=$(echo -e "$ISSUES" | sed '/^$/d')

if [ -n "$ISSUES" ]; then
  echo "STUB/PLACEHOLDER DETECTED in $FILE_PATH:" >&2
  echo -e "$ISSUES" >&2
  echo "" >&2
  echo "MANDATORY: Fix these violations NOW before doing anything else." >&2
  echo "Rule: No stubs, TODOs, or placeholder implementations." >&2
  echo "WARNING: TaskCompleted hook WILL BLOCK completion if these remain." >&2
  echo "Action: Re-read the file, fix every violation, then continue." >&2
  HOOK_DECISION="warn" HOOK_REASON="stubs detected in $FILE_PATH"
  record_hook_outcome "verify-no-stubs" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 2
fi

record_hook_outcome "verify-no-stubs" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
