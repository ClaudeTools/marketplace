#!/usr/bin/env bash
# validate-hook.sh — Check a hook script follows Claude Code conventions
# Usage: bash validate-hook.sh /path/to/hook-script.sh
set -euo pipefail

SCRIPT_PATH="${1:-}"
if [ -z "$SCRIPT_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
  echo "Usage: bash validate-hook.sh /path/to/hook-script.sh"
  exit 1
fi

ERRORS=0
WARNINGS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

BASENAME=$(basename "$SCRIPT_PATH")
CONTENT=$(cat "$SCRIPT_PATH")

echo "=== Validating hook script: $BASENAME ==="
echo ""

# --- Syntax ---
echo "--- Syntax ---"

if bash -n "$SCRIPT_PATH" 2>/dev/null; then
  pass "bash -n syntax check"
else
  fail "bash -n syntax check failed"
fi

# --- Shell safety ---
echo ""
echo "--- Shell Safety ---"

# Check for set -euo pipefail (or set -e at minimum)
if echo "$CONTENT" | grep -qE '^set -[a-z]*e[a-z]*'; then
  if echo "$CONTENT" | grep -q 'set -euo pipefail'; then
    pass "set -euo pipefail"
  else
    warn "uses set -e but not full set -euo pipefail"
  fi
else
  fail "missing set -e — script will not exit on errors"
fi

# Check shebang
FIRST_LINE=$(head -1 "$SCRIPT_PATH")
if echo "$FIRST_LINE" | grep -qE '^#!/(usr/)?bin/(env )?bash'; then
  pass "valid bash shebang"
else
  fail "missing or invalid shebang (expected #!/bin/bash or #!/usr/bin/env bash)"
fi

# --- Hook Interface ---
echo ""
echo "--- Hook Interface ---"

# Check for stdin consumption (hook_init or cat)
if echo "$CONTENT" | grep -qE 'hook_init|INPUT=\$\(cat'; then
  pass "stdin consumed (hook_init or cat)"
  # Check stdin is consumed early (within first 20 lines)
  STDIN_LINE=$(echo "$CONTENT" | grep -nE 'hook_init|INPUT=\$\(cat' | head -1 | cut -d: -f1)
  if [ -n "$STDIN_LINE" ] && [ "$STDIN_LINE" -le 20 ]; then
    pass "stdin consumed early (line $STDIN_LINE)"
  else
    warn "stdin consumed late (line ${STDIN_LINE:-?}) — should be in first 15-20 lines before any other I/O"
  fi
else
  warn "no stdin consumption found — hooks receive JSON on stdin (use hook_init or INPUT=\$(cat))"
fi

# Check for sourcing hook-input.sh
if echo "$CONTENT" | grep -q 'lib/hook-input.sh'; then
  pass "sources lib/hook-input.sh"
else
  warn "does not source lib/hook-input.sh — consider using shared hook input parsing"
fi

# --- Exit Code Contract ---
echo ""
echo "--- Exit Codes ---"

# Check for exit statements
EXIT_COUNT=$(echo "$CONTENT" | grep -cE '^\s*(exit|return) [0-2]' || true)
if [ "$EXIT_COUNT" -gt 0 ]; then
  pass "explicit exit/return codes found ($EXIT_COUNT)"
else
  warn "no explicit exit codes — hooks use 0=allow, 1=warn, 2=block"
fi

# Check for exit codes > 2 (non-standard)
BAD_EXITS=$(echo "$CONTENT" | grep -nE '^\s*exit [3-9]|^\s*exit [0-9]{2,}' || true)
if [ -n "$BAD_EXITS" ]; then
  fail "non-standard exit codes found (only 0, 1, 2 are valid for hooks):"
  echo "    $BAD_EXITS"
else
  pass "no non-standard exit codes"
fi

# --- Session & Worktree Safety ---
echo ""
echo "--- Session & Worktree Safety ---"

# Check for PPID usage (should use session_id)
if echo "$CONTENT" | grep -qE '\$PPID|\$\{PPID\}'; then
  PPID_LINES=$(echo "$CONTENT" | grep -nE '\$PPID|\$\{PPID\}' | head -3)
  warn "uses \$PPID — prefer get_session_id from lib/worktree.sh for session isolation:"
  echo "    $PPID_LINES"
else
  pass "no PPID usage"
fi

# Check for bare $(pwd) usage
if echo "$CONTENT" | grep -qE '\$\(pwd\)'; then
  PWD_LINES=$(echo "$CONTENT" | grep -nE '\$\(pwd\)' | head -3)
  warn "uses \$(pwd) — in worktrees this returns the worktree path, not repo root. Use get_repo_root or CWD from hook input:"
  echo "    $PWD_LINES"
else
  pass "no bare \$(pwd) usage"
fi

# Check for bare git commands (without -C flag)
BARE_GIT=$(echo "$CONTENT" | grep -nE '^\s*(git |.*\$\(git )' | grep -vE -- '-C |rev-parse --git' | head -5 || true)
if [ -n "$BARE_GIT" ]; then
  warn "bare git commands found (may fail in worktrees — use git -C \"\$CWD\"):"
  echo "    $BARE_GIT"
else
  pass "no bare git commands (all use -C flag or worktree-safe patterns)"
fi

# --- Graceful Degradation ---
echo ""
echo "--- Graceful Degradation ---"

# Check for unguarded external tool calls
UNGUARDED_NODE=$(echo "$CONTENT" | grep -nE '^\s*node ' | grep -v '2>/dev/null' | grep -v '|| true' | head -3 || true)
if [ -n "$UNGUARDED_NODE" ]; then
  warn "unguarded node calls (add 2>/dev/null || true):"
  echo "    $UNGUARDED_NODE"
fi

UNGUARDED_SQLITE=$(echo "$CONTENT" | grep -nE '^\s*sqlite3 ' | grep -v '2>/dev/null' | grep -v '|| true' | head -3 || true)
if [ -n "$UNGUARDED_SQLITE" ]; then
  warn "unguarded sqlite3 calls (add 2>/dev/null || true):"
  echo "    $UNGUARDED_SQLITE"
fi

# Check for command existence guards
if echo "$CONTENT" | grep -qE 'command -v|which '; then
  pass "command existence checks found"
fi

# --- Performance ---
echo ""
echo "--- Performance ---"

LINE_COUNT=$(wc -l < "$SCRIPT_PATH")
if [ "$LINE_COUNT" -gt 300 ]; then
  warn "script is $LINE_COUNT lines — consider splitting into dispatcher + validators for maintainability"
fi

# Check for sleep calls (should not be in sync hooks)
if echo "$CONTENT" | grep -qE '^\s*sleep '; then
  fail "sleep found — synchronous hooks must complete in <100ms"
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
