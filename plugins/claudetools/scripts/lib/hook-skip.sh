#!/usr/bin/env bash
# hook-skip.sh — Shared skip-pattern library for content validation hooks
#
# All functions take a file path as $1 and return:
#   0 = should skip (true)
#   1 = should NOT skip (false)
#
# Pure case-statements — no subshells, fast for per-file use.

# is_test_file — Returns 0 if the path looks like a test/mock/fixture file.
is_test_file() {
  case "${1:-}" in
    *.test.*|*.spec.*|*__tests__*|*__mocks__*|*.stories.*|*.story.*|*fixtures*|*__fixtures__*|*.mock.*)
      return 0 ;;
  esac
  return 1
}

# is_doc_file — Returns 0 if the path is a documentation file.
is_doc_file() {
  case "${1:-}" in
    *.md|*.txt|*.rst|*.adoc)
      return 0 ;;
  esac
  return 1
}

# is_config_file — Returns 0 if the path is a config or data file.
is_config_file() {
  case "${1:-}" in
    *.json|*.yaml|*.yml|*.toml|*.lock|*.config.*|*.rc|.env*)
      return 0 ;;
  esac
  return 1
}

# is_binary_file — Returns 0 if the path is a binary or generated asset.
is_binary_file() {
  case "${1:-}" in
    *.lock|*.sum|*.svg|*.png|*.jpg|*.gif|*.ico|*.woff*|*.ttf|*.eot)
      return 0 ;;
  esac
  return 1
}

# is_non_code_file — Returns 0 if the path is NOT a source code file.
# Combines doc + config + binary checks.
is_non_code_file() {
  is_doc_file    "${1:-}" && return 0
  is_config_file "${1:-}" && return 0
  is_binary_file "${1:-}" && return 0
  return 1
}

# should_skip_content_check — Master skip gate for content validation hooks.
# Returns 0 if the file should be skipped entirely.
# Checks (in order):
#   1. No file path provided
#   2. File does not exist on disk
#   3. Test / mock / fixture file
#   4. Documentation file
#   5. Shell script
#   6. File lives inside .claude/hooks/
should_skip_content_check() {
  local file="${1:-}"

  # 1. No path
  [[ -z "$file" ]] && return 0

  # 2. File does not exist
  [[ ! -f "$file" ]] && return 0

  # 3. Test / mock / fixture
  is_test_file "$file" && return 0

  # 4. Documentation
  is_doc_file "$file" && return 0

  # 5. Shell script
  case "$file" in
    *.sh) return 0 ;;
  esac

  # 6. Hook scripts themselves
  case "$file" in
    */.claude/hooks/*) return 0 ;;
  esac

  # 7. Temporary files (scripts in /tmp/)
  case "$file" in
    /tmp/*) return 0 ;;
  esac

  return 1
}
