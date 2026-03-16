#!/bin/bash
# PostToolUse:Edit|Write hook — warns when mock/fake data patterns appear outside test files
# Enforces: no-shortcuts.md "No mocks or fake data outside test files"
# Exit 1 = warn (non-blocking), Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the file path that was just written/edited
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip test files — mocks are expected there
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__*|*__mocks__*|*.stories.*|*.story.*|*fixtures*|*__fixtures__*|*.mock.*)
    exit 0
    ;;
esac

# Skip non-code files
case "$FILE_PATH" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.sh|*.css|*.svg|*.png|*.jpg|*.gif)
    exit 0
    ;;
esac

# --- Check tool_input.new_string for mock patterns (catches at write time) ---
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null || true)
INLINE_MOCK_PATTERNS='jest\.fn|vi\.mock|sinon\.|mockData|mock\(\)|createMock'

if [ -n "$NEW_STRING" ]; then
  INLINE_HITS=$(echo "$NEW_STRING" | grep -cE "$INLINE_MOCK_PATTERNS" 2>/dev/null || echo "0")
  if [ "$INLINE_HITS" -gt 0 ]; then
    BASENAME=$(basename "$FILE_PATH")
    HOOK_DECISION="warn" HOOK_REASON="mock patterns in new_string content"
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
    record_hook_outcome "check-mock-in-prod" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
    exit 1
  fi
fi

# --- Check file on disk for mock patterns ---
# Resolve relative path
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
[ "${FILE_PATH:0:1}" != "/" ] && FILE_PATH="$CWD/$FILE_PATH"
[ -f "$FILE_PATH" ] || exit 0

MOCK_PATTERNS='jest\.fn\(|jest\.mock\(|jest\.spyOn\(|vi\.fn\(|vi\.mock\(|vi\.spyOn\(|sinon\.(stub|mock|fake|spy)|\.stub\(|\.mock\(|mockImplementation|mockReturnValue|mockResolvedValue|mockRejectedValue'
FAKE_PATTERNS='fake[A-Z][a-zA-Z]+\s*=|mock[A-Z][a-zA-Z]+\s*[:=]|const\s+mock[A-Z]|let\s+mock[A-Z]|var\s+mock[A-Z]'

MOCK_COUNT=$(grep -cE "$MOCK_PATTERNS" "$FILE_PATH" 2>/dev/null || echo "0")
FAKE_COUNT=$(grep -cE "$FAKE_PATTERNS" "$FILE_PATH" 2>/dev/null || echo "0")

TOTAL=$((MOCK_COUNT + FAKE_COUNT))

if [ "$TOTAL" -gt 0 ]; then
  BASENAME=$(basename "$FILE_PATH")
  HOOK_DECISION="warn" HOOK_REASON="mock/fake patterns in production code"

  MATCHES=$(grep -nE "$MOCK_PATTERNS|$FAKE_PATTERNS" "$FILE_PATH" 2>/dev/null | head -5)

  echo "MOCK/FAKE DATA WARNING: ${TOTAL} mock/fake patterns found in production file: ${BASENAME}"
  echo ""
  echo "Rule: No mocks or fake data outside test files (no-shortcuts.md)"
  echo ""
  echo "Matches:"
  echo "$MATCHES"
  echo ""
  echo "If this is NOT a test file, remove mock/fake patterns and use real implementations."
  echo "If this IS a test file, rename it to include .test. or .spec. in the filename."
  record_hook_outcome "check-mock-in-prod" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 1
fi

record_hook_outcome "check-mock-in-prod" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
