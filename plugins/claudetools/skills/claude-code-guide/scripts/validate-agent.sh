#!/usr/bin/env bash
# validate-agent.sh — Check an agent definition follows Claude Code conventions
# Usage: bash validate-agent.sh /path/to/agent.md
set -euo pipefail

AGENT_PATH="${1:-}"
if [ -z "$AGENT_PATH" ] || [ ! -f "$AGENT_PATH" ]; then
  echo "Usage: bash validate-agent.sh /path/to/agent.md"
  exit 1
fi

ERRORS=0
WARNINGS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

BASENAME=$(basename "$AGENT_PATH" .md)
CONTENT=$(cat "$AGENT_PATH")

echo "=== Validating agent: $BASENAME ==="
echo ""

# --- Frontmatter ---
echo "--- Frontmatter ---"

# Check for YAML frontmatter
if head -1 "$AGENT_PATH" | grep -q '^---$'; then
  pass "frontmatter opening delimiter"
else
  fail "missing YAML frontmatter (file must start with ---)"
  echo ""
  echo "RESULT: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
fi

# Extract frontmatter
FRONTMATTER=$(sed -n '2,/^---$/p' "$AGENT_PATH" | sed '$d')
CLOSING_LINE=$(grep -n '^---$' "$AGENT_PATH" | sed -n '2p' | cut -d: -f1)

if [ -n "$CLOSING_LINE" ]; then
  pass "frontmatter closing delimiter (line $CLOSING_LINE)"
else
  fail "missing frontmatter closing delimiter (---)"
fi

# Check name field
NAME=$(echo "$FRONTMATTER" | grep -oP '^name:\s*\K.*' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
if [ -n "$NAME" ]; then
  pass "name field: $NAME"
  # Check name matches filename
  NAME_CLEAN=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  BASENAME_CLEAN=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')
  if [ "$NAME_CLEAN" = "$BASENAME_CLEAN" ] || [ "$(echo "$NAME" | tr -d ' ')" = "$BASENAME" ]; then
    pass "name aligns with filename"
  else
    warn "name '$NAME' may not match filename '$BASENAME' — agents are invoked by filename"
  fi
else
  fail "missing 'name' field — required for agent identity"
fi

# Check description field
DESC=$(echo "$FRONTMATTER" | grep -oP '^description:\s*\K.*' || true)
if [ -n "$DESC" ]; then
  DESC_LEN=${#DESC}
  pass "description field ($DESC_LEN chars)"
  if [ "$DESC_LEN" -lt 30 ]; then
    warn "description is very short ($DESC_LEN chars) — should explain what the agent does and when to use it"
  fi
else
  fail "missing 'description' field — the Agent tool uses this to select the right agent"
fi

# --- Optional Fields ---
echo ""
echo "--- Configuration ---"

# Check for disallowedTools
DISALLOWED=$(echo "$FRONTMATTER" | grep -oP '^disallowedTools:\s*\K.*' || true)
if [ -n "$DISALLOWED" ]; then
  pass "disallowedTools defined: $DISALLOWED"
  # Check for common read-only patterns
  if echo "$DISALLOWED" | grep -qE 'Edit|Write|Bash'; then
    pass "tool restrictions include write/execute tools (read-only agent pattern)"
  fi
else
  warn "no disallowedTools — agent has full tool access. Restrict tools for safety-critical roles"
fi

# Check for model
MODEL=$(echo "$FRONTMATTER" | grep -oP '^model:\s*\K.*' || true)
if [ -n "$MODEL" ]; then
  pass "model specified: $MODEL"
  case "$MODEL" in
    *sonnet*|*haiku*|*opus*)
      pass "recognized model family"
      ;;
    *)
      warn "unrecognized model '$MODEL' — use sonnet (default), haiku (fast), or opus (complex)"
      ;;
  esac
fi

# --- Body Content ---
echo ""
echo "--- Body Content ---"

# Count body lines (after frontmatter)
if [ -n "$CLOSING_LINE" ]; then
  BODY_LINES=$(($(wc -l < "$AGENT_PATH") - CLOSING_LINE))
else
  BODY_LINES=0
fi

if [ "$BODY_LINES" -gt 5 ]; then
  pass "body has $BODY_LINES lines of role description"
else
  warn "body is only $BODY_LINES lines — provide enough context for the agent to understand its role"
fi

# Check for role identity
BODY=$(tail -n +"$((CLOSING_LINE + 1))" "$AGENT_PATH" 2>/dev/null || true)

if echo "$BODY" | grep -qiE 'you are|your role|your job|your task|as a'; then
  pass "role identity statement found"
else
  warn "no clear role identity — start with 'You are a...' to establish the agent's persona"
fi

# Check for output format guidance
if echo "$BODY" | grep -qiE 'output|format|return|report|respond|produce'; then
  pass "output format guidance found"
else
  warn "no output format guidance — tell the agent what its deliverable looks like"
fi

# Check for constraint/scope section
if echo "$BODY" | grep -qiE 'constraint|scope|must not|do not|avoid|restrict|limit'; then
  pass "constraints or scope boundaries found"
else
  warn "no constraints section — define what the agent should NOT do"
fi

# --- Size ---
echo ""
echo "--- Size ---"

TOTAL_LINES=$(wc -l < "$AGENT_PATH")
if [ "$TOTAL_LINES" -gt 200 ]; then
  warn "agent definition is $TOTAL_LINES lines — keep it focused. Consider splitting complex logic into a skill instead"
elif [ "$TOTAL_LINES" -lt 10 ]; then
  warn "agent definition is only $TOTAL_LINES lines — may not have enough context for reliable behavior"
fi

# --- Summary ---
echo ""
echo "=== RESULT ==="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
elif [ "$ERRORS" -eq 0 ]; then
  echo "PASSED with $WARNINGS warning(s)"
else
  echo "FAILED: $ERRORS error(s), $WARNINGS warning(s)"
fi
exit "$ERRORS"
