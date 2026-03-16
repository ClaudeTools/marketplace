#!/usr/bin/env bash
# validate-prompt.sh
# Validates a generated XML prompt for required structural elements.
# Usage: echo "$prompt" | bash validate-prompt.sh
#        bash validate-prompt.sh prompt-file.md
set -euo pipefail

# Read prompt from file argument or stdin
if [ "${1:-}" ] && [ -f "$1" ]; then
  PROMPT=$(cat "$1")
else
  PROMPT=$(cat)
fi

ERRORS=0
WARNINGS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

# --- Required element checks ---

# 1. At least one <task> block exists
TASK_COUNT=$(echo "$PROMPT" | grep -c '<task' || true)
if [ "$TASK_COUNT" -gt 0 ]; then
  pass "task blocks found ($TASK_COUNT)"
else
  fail "no task blocks found"
fi

# 2. Every <task> block contains a <verification> section
VERIFICATION_COUNT=$(echo "$PROMPT" | grep -c '<verification' || true)
if [ "$TASK_COUNT" -gt 0 ]; then
  if [ "$VERIFICATION_COUNT" -ge "$TASK_COUNT" ]; then
    pass "all tasks have verification ($VERIFICATION_COUNT/$TASK_COUNT)"
  else
    fail "not all tasks have verification ($VERIFICATION_COUNT/$TASK_COUNT)"
  fi
fi

# 3. A <check> block exists
if echo "$PROMPT" | grep -q '<check'; then
  pass "check block present"
else
  fail "no check block found"
fi

# 4. A typecheck command appears somewhere
if echo "$PROMPT" | grep -qiE '(tsc|pyright|mypy|go vet|cargo check|cargo test)'; then
  pass "typecheck command found"
else
  fail "no typecheck command found"
fi

# 5. An <escape> clause exists (in execution block or standalone)
if echo "$PROMPT" | grep -q '<escape'; then
  pass "escape clause present"
else
  warn "no escape clause found — add <escape> to prevent hallucinated workarounds"
fi

# --- Quality warnings (non-blocking) ---

# Vague adjectives
VAGUE_WORDS="scalable|robust|clean|modern|good|proper|appropriate|efficient"
while IFS= read -r match; do
  if [ -n "$match" ]; then
    warn "vague adjective \"$match\" detected"
  fi
done < <(echo "$PROMPT" | grep -oiE "\b($VAGUE_WORDS)\b" | tr '[:upper:]' '[:lower:]' | sort -u || true)

# No <approach> block (replaced <evaluate>)
if ! echo "$PROMPT" | grep -q '<approach'; then
  warn "no approach block found — consider adding think-before-act reasoning"
fi

# Aggressive language detection
AGGRESSIVE_WORDS="MUST|NEVER|CRITICAL|non-negotiable|ABSOLUTELY|NO exceptions"
AGGRESSIVE_MATCHES=$(echo "$PROMPT" | grep -oE "\b($AGGRESSIVE_WORDS)\b" || true)
AGGRESSIVE_COUNT=$(echo "$AGGRESSIVE_MATCHES" | grep -c . || true)
if [ "$AGGRESSIVE_COUNT" -gt 2 ]; then
  warn "aggressive language detected ($AGGRESSIVE_COUNT instances) — use calm, direct instructions"
fi

# Prompt exceeds 120 lines without phasing
LINE_COUNT=$(echo "$PROMPT" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -gt 120 ]; then
  if ! echo "$PROMPT" | grep -q '<phase'; then
    warn "prompt exceeds 120 lines ($LINE_COUNT) without phasing"
  fi
fi

# Check block quality
if echo "$PROMPT" | grep -q '<check'; then
  # File re-read
  if ! echo "$PROMPT" | grep -qi 're-read\|reread\|verify.*changed.*file\|scan.*changed'; then
    fail "check block missing file re-read verification"
  fi
  # Typecheck in check block
  if ! echo "$PROMPT" | grep -qi 'typecheck\|tsc.*noEmit\|pyright\|cargo check'; then
    warn "check block missing typecheck command"
  fi
  # Test suite
  if ! echo "$PROMPT" | grep -qi 'test suite\|npm test\|run.*test'; then
    warn "check block missing test suite execution"
  fi
fi

# Constraints section — check for generic boilerplate
if echo "$PROMPT" | grep -qi '<constraints'; then
  # Warn on generic boilerplate that belongs in verification/check blocks
  GENERIC_PATTERNS="no stubs|no placeholder|re-read.*file|run.*test.*after|deterministic.*operation|bash.*for.*all"
  GENERIC_COUNT=$(echo "$PROMPT" | sed -n '/<constraints/,/<\/constraints/p' | grep -ciE "$GENERIC_PATTERNS" || true)
  if [ "$GENERIC_COUNT" -gt 2 ]; then
    warn "constraints contain $GENERIC_COUNT generic rules — move these to verification/check blocks, keep constraints task-specific"
  fi
fi

# UI tasks should mention visual verification
if echo "$PROMPT" | grep -qiE '(component|page|ui|ux|layout|responsive|css|tailwind|frontend)'; then
  if ! echo "$PROMPT" | grep -qiE '(chrome|browser|screenshot|visual.*verif|viewport|breakpoint)'; then
    warn "UI-related task missing visual verification requirement"
  fi
fi

# Deprecated pattern warnings
if echo "$PROMPT" | grep -q '<evaluate'; then
  warn "<evaluate> is deprecated — use <approach> for think-before-act reasoning"
fi
if echo "$PROMPT" | grep -qi 'sequential.thinking\|sequentialthinking'; then
  warn "sequential-thinking MCP reference detected — use native <approach> blocks instead"
fi

# --- Final summary ---
echo ""
if [ "$ERRORS" -eq 0 ]; then
  if [ "$WARNINGS" -gt 0 ]; then
    echo "VALIDATION: PASS ($WARNINGS warning(s))"
  else
    echo "VALIDATION: PASS"
  fi
  exit 0
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo "VALIDATION: FAIL ($ERRORS error(s), $WARNINGS warning(s))"
  else
    echo "VALIDATION: FAIL ($ERRORS error(s))"
  fi
  exit 1
fi
