#!/bin/bash
# Validator: mock/fake data pattern detection outside test files
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: FILE_PATH, BASENAME, INPUT
# Calls: hook_get_content (lazy NEW_STRING extraction)
# Returns: 0 = clean, 1 = mocks found (warning)
# Output: findings written to stdout

validate_mocks() {
  # Skip test files — mocks are expected there
  # (dispatcher may already handle this, but kept for safety)
  is_test_file "$FILE_PATH" && return 0

  # Skip non-code files
  case "$FILE_PATH" in
    *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh|*.css|*.svg|*.png|*.jpg|*.gif)
      return 0
      ;;
  esac

  # --- Check tool_input.new_string for mock patterns (catches at write time) ---
  local NEW_STRING
  NEW_STRING=$(hook_get_content)
  local INLINE_MOCK_PATTERNS='jest\.fn|vi\.mock|sinon\.|mockData|mock\(\)|createMock'

  if [ -n "$NEW_STRING" ]; then
    local INLINE_HITS
    INLINE_HITS=$(echo "$NEW_STRING" | grep -cE "$INLINE_MOCK_PATTERNS" 2>/dev/null); INLINE_HITS=${INLINE_HITS:-0}
    if [ "$INLINE_HITS" -gt 0 ]; then
      local INLINE_MATCHES
      INLINE_MATCHES=$(echo "$NEW_STRING" | grep -nE "$INLINE_MOCK_PATTERNS" 2>/dev/null | head -5)
      echo "MOCK/FAKE DATA WARNING: ${INLINE_HITS} mock pattern(s) being written to production file: ${BASENAME}"
      echo ""
      echo "Rule: No mocks or fake data outside test files (no-shortcuts.md)"
      echo ""
      echo "Matches in new content:"
      echo "$INLINE_MATCHES"
      echo ""
      echo "If this is NOT a test file, remove mock/fake patterns and use real implementations."
      echo "If this IS a test file, rename it to include .test. or .spec. in the filename."
      return 1
    fi
  fi

  # --- Check file on disk for mock patterns ---
  # Resolve relative path
  local RESOLVED_PATH="$FILE_PATH"
  local CWD
  CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
  [ "${RESOLVED_PATH:0:1}" != "/" ] && RESOLVED_PATH="$CWD/$RESOLVED_PATH"
  [ -f "$RESOLVED_PATH" ] || return 0

  local MOCK_PATTERNS='jest\.fn\(|jest\.mock\(|jest\.spyOn\(|vi\.fn\(|vi\.mock\(|vi\.spyOn\(|sinon\.(stub|mock|fake|spy)|\.stub\(|\.mock\(|mockImplementation|mockReturnValue|mockResolvedValue|mockRejectedValue'
  local FAKE_PATTERNS='fake[A-Z][a-zA-Z]+\s*=|mock[A-Z][a-zA-Z]+\s*[:=]|const\s+mock[A-Z]|let\s+mock[A-Z]|var\s+mock[A-Z]'

  local MOCK_COUNT
  MOCK_COUNT=$(grep -cE "$MOCK_PATTERNS" "$RESOLVED_PATH" 2>/dev/null); MOCK_COUNT=${MOCK_COUNT:-0}
  local FAKE_COUNT
  FAKE_COUNT=$(grep -cE "$FAKE_PATTERNS" "$RESOLVED_PATH" 2>/dev/null); FAKE_COUNT=${FAKE_COUNT:-0}

  local TOTAL=$((MOCK_COUNT + FAKE_COUNT))

  if [ "$TOTAL" -gt 0 ]; then
    local MATCHES
    MATCHES=$(grep -nE "$MOCK_PATTERNS|$FAKE_PATTERNS" "$RESOLVED_PATH" 2>/dev/null | head -5)

    echo "MOCK/FAKE DATA WARNING: ${TOTAL} mock/fake patterns found in production file: ${BASENAME}"
    echo ""
    echo "Rule: No mocks or fake data outside test files (no-shortcuts.md)"
    echo ""
    echo "Matches:"
    echo "$MATCHES"
    echo ""
    echo "If this is NOT a test file, remove mock/fake patterns and use real implementations."
    echo "If this IS a test file, rename it to include .test. or .spec. in the filename."
    return 1
  fi

  return 0
}
