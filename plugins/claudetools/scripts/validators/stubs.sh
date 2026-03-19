#!/bin/bash
# Validator: stub/placeholder/shortcut detection
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: FILE_PATH, FILE_EXT, BASENAME, MODEL_FAMILY
# Calls: hook_get_content (lazy NEW_STRING extraction), get_threshold
# Returns: 0 = clean, 2 = stubs found (blocking)
# Output: findings written to stdout

validate_stubs() {
  ISSUES=""
  local add_line
  add_line() { while IFS= read -r line; do ISSUES="${ISSUES}${line}\n"; done; }

  # --- Language-specific stub detection, gated by file extension ---
  case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx)
      # TypeScript/JavaScript stub throws
      add_line < <(grep -n -E \
        'throw new Error\(.*(not implemented|todo|fixme|placeholder)' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME/HACK comment markers (JS-style)
      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)

      # Empty function bodies
      add_line < <(grep -n -E \
        '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}' \
        "$FILE_PATH" 2>/dev/null || true)

      # Functions whose body is only console.log/console.error/console.warn (single-line)
      add_line < <(grep -n -E \
        '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*console\.(log|error|warn)\(.*\);\s*\}' \
        "$FILE_PATH" 2>/dev/null || true)

      # Hardcoded return shortcuts (sole statement in function body, single-line)
      add_line < <(grep -n -E \
        '(async\s+)?function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*return\s+(null|undefined|\{\}|\[\])\s*;?\s*\}' \
        "$FILE_PATH" 2>/dev/null || true)

      # Arrow functions with hardcoded return shortcuts
      add_line < <(grep -n -E \
        '=>\s*(\(\s*)?(null|undefined|\{\}|\[\])(\s*\))?\s*[;,]' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.py)
      # Skip .pyi type stub files — these are legitimate Python type annotations
      case "$FILE_PATH" in *.pyi) return 0 ;; esac

      # Python stubs
      add_line < <(grep -n -E \
        'raise\s+NotImplementedError' \
        "$FILE_PATH" 2>/dev/null || true)

      # pass as only function body (line contains only whitespace + pass)
      # Filter out legitimate except/else: pass patterns
      add_line < <(grep -n -E '^\s*pass\s*$' "$FILE_PATH" 2>/dev/null | while IFS=: read -r lineno rest; do
        # Check if the previous line is an except or else clause
        prev_line=$(sed -n "$((lineno - 1))p" "$FILE_PATH" 2>/dev/null || true)
        if ! echo "$prev_line" | grep -qE '^\s*(except|else)\s*:'; then
          echo "${lineno}:${rest}"
        fi
      done || true)

      # Ellipsis as only function body (line contains only whitespace + ...)
      add_line < <(grep -n -E \
        '^\s*\.\.\.\s*$' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (Python-style)
      add_line < <(grep -n -E \
        '#\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.rs)
      # Rust stubs
      add_line < <(grep -n -E \
        'todo!\(\)|unimplemented!\(\)|panic!\("not implemented"\)' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (Rust-style)
      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.go)
      # Go stubs
      add_line < <(grep -n -E \
        'panic\("not implemented"\)' \
        "$FILE_PATH" 2>/dev/null || true)

      # Functions with only return nil or return ""
      add_line < <(grep -n -E \
        '^\s*return\s+(nil|"")\s*$' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (Go-style)
      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.java)
      # Java stubs
      add_line < <(grep -n -E \
        'throw new UnsupportedOperationException' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (Java-style)
      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.cs)
      # C# stubs
      add_line < <(grep -n -E \
        'throw new NotImplementedException' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (C#-style)
      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.rb)
      # Ruby stubs
      add_line < <(grep -n -E \
        'raise\s+NotImplementedError' \
        "$FILE_PATH" 2>/dev/null || true)

      # TODO/FIXME comment markers (Ruby-style)
      add_line < <(grep -n -E \
        '#\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.kt|*.kts)
      # Kotlin stubs
      add_line < <(grep -n -E \
        'TODO\(\)|throw NotImplementedError|throw UnsupportedOperationException' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.swift)
      # Swift stubs
      add_line < <(grep -n -E \
        'fatalError\(.*(not implemented|todo|placeholder)|preconditionFailure' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.cpp|*.cc|*.cxx|*.c|*.h|*.hpp)
      # C/C++ stubs
      add_line < <(grep -n -E \
        'throw\s+std::runtime_error\(.*(not implemented|todo)|static_assert\(false' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.php)
      # PHP stubs
      add_line < <(grep -n -E \
        'throw new \\?(BadMethodCallException|RuntimeException)\(.*(not implemented|todo)' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.scala)
      # Scala stubs
      add_line < <(grep -n -E \
        '\?\?\?|throw new NotImplementedError|throw new UnsupportedOperationException' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.lua)
      # Lua stubs
      add_line < <(grep -n -E \
        'error\(.*(not implemented|todo|placeholder)' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '--\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.zig)
      # Zig stubs
      add_line < <(grep -n -E \
        '@panic\(.*(not implemented|todo)|unreachable' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '//\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;

    *.ex|*.exs)
      # Elixir stubs
      add_line < <(grep -n -E \
        'raise\s+"not implemented"|raise\s+RuntimeError' \
        "$FILE_PATH" 2>/dev/null || true)

      add_line < <(grep -n -E \
        '#\s*(TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER):?\s' \
        "$FILE_PATH" 2>/dev/null || true)
      ;;
  esac

  # --- Multi-line stub detection: function body is ONLY return []/{}/ null (across lines) ---
  # Uses awk to find functions where the only statement between { and } is a return of empty data
  add_line < <(awk '
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
  add_line < <(awk '
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
      local TS_ANY_LIMIT
      TS_ANY_LIMIT=$(get_threshold "ts_any_limit" "$MODEL_FAMILY")
      TS_ANY_LIMIT=${TS_ANY_LIMIT%.*}
      local ANY_COUNT
      ANY_COUNT=$({ grep -o ': any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$ANY_COUNT" -gt "$TS_ANY_LIMIT" ]; then
        ISSUES="${ISSUES}WARNING: ${ANY_COUNT} uses of ': any' -- likely type shortcuts\n"
      fi

      # 'as any' cast abuse
      local TS_AS_ANY_LIMIT
      TS_AS_ANY_LIMIT=$(get_threshold "ts_as_any_limit" "$MODEL_FAMILY")
      TS_AS_ANY_LIMIT=${TS_AS_ANY_LIMIT%.*}
      local AS_ANY_COUNT
      AS_ANY_COUNT=$({ grep -o 'as any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$AS_ANY_COUNT" -gt "$TS_AS_ANY_LIMIT" ]; then
        ISSUES="${ISSUES}WARNING: ${AS_ANY_COUNT} uses of 'as any' -- unsafe type casts\n"
      fi

      # @ts-ignore / @ts-expect-error abuse
      local TS_IGNORE_LIMIT
      TS_IGNORE_LIMIT=$(get_threshold "ts_ignore_limit" "$MODEL_FAMILY")
      TS_IGNORE_LIMIT=${TS_IGNORE_LIMIT%.*}
      local TS_SUPPRESS
      TS_SUPPRESS=$({ grep -oE '@ts-ignore|@ts-expect-error' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$TS_SUPPRESS" -gt "$TS_IGNORE_LIMIT" ]; then
        ISSUES="${ISSUES}WARNING: ${TS_SUPPRESS} uses of @ts-ignore/@ts-expect-error -- suppressing type safety\n"
      fi
      ;;

    *.py)
      # Python type safety: excessive Any usage
      local PY_ANY_COUNT
      PY_ANY_COUNT=$({ grep -oE ':\s*Any\b|->.*Any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$PY_ANY_COUNT" -gt 5 ]; then
        ISSUES="${ISSUES}WARNING: ${PY_ANY_COUNT} uses of 'Any' type -- likely type shortcuts\n"
      fi

      # Python: bare except (catches everything including KeyboardInterrupt)
      local BARE_EXCEPT
      BARE_EXCEPT=$({ grep -n -E '^\s*except\s*:' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$BARE_EXCEPT" -gt 0 ]; then
        ISSUES="${ISSUES}WARNING: ${BARE_EXCEPT} bare except clauses -- should catch specific exceptions\n"
      fi

      # Python: type: ignore abuse
      local PY_IGNORE
      PY_IGNORE=$({ grep -oE '#\s*type:\s*ignore' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$PY_IGNORE" -gt 2 ]; then
        ISSUES="${ISSUES}WARNING: ${PY_IGNORE} uses of '# type: ignore' -- suppressing type safety\n"
      fi
      ;;

    *.go)
      # Go type safety: excessive interface{} / any usage
      local GO_IFACE_COUNT
      GO_IFACE_COUNT=$({ grep -oE 'interface\{\}|any\b' "$FILE_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [ "$GO_IFACE_COUNT" -gt 5 ]; then
        ISSUES="${ISSUES}WARNING: ${GO_IFACE_COUNT} uses of interface{}/any -- consider typed parameters\n"
      fi
      ;;
  esac

  # Clean up empty lines
  ISSUES=$(echo -e "$ISSUES" | sed '/^$/d')

  if [ -n "$ISSUES" ]; then
    echo "Stubs detected in $FILE_PATH:"
    echo -e "$ISSUES"
    echo ""
    echo "Stubs cause runtime crashes and hide incomplete work from reviewers."
    echo "Replace each stub with a working implementation, then continue."
    return 2
  fi

  return 0
}
