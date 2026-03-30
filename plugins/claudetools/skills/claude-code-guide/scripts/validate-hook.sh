#!/usr/bin/env bash
# validate-hook.sh — Check a hook script follows Claude Code conventions
# Usage: bash validate-hook.sh /path/to/hook-script.sh
set -euo pipefail

SCRIPT_PATH="${1:-}"
if [ -z "$SCRIPT_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
  echo "Usage: bash validate-hook.sh /path/to/hook-script.sh"
  exit 1
fi

# shellcheck source=lib/validator-framework.sh
source "$(dirname "$0")/lib/validator-framework.sh"

BASENAME=$(basename "$SCRIPT_PATH")
CONTENT=$(cat "$SCRIPT_PATH")

echo "=== Validating hook script: $BASENAME ==="
echo ""

# --- Syntax ---
vf_section "Syntax"

if bash -n "$SCRIPT_PATH" 2>/dev/null; then
  vf_pass "bash -n syntax check"
else
  vf_fail "bash -n syntax check failed"
fi

# --- Shell safety ---
vf_section "Shell Safety"

# Check for set -euo pipefail (or set -e at minimum)
if echo "$CONTENT" | grep -qE '^set -[a-z]*e[a-z]*'; then
  if echo "$CONTENT" | grep -q 'set -euo pipefail'; then
    vf_pass "set -euo pipefail"
  else
    vf_warn "uses set -e but not full set -euo pipefail"
  fi
else
  vf_fail "missing set -e — script will not exit on errors"
fi

# Check shebang
FIRST_LINE=$(head -1 "$SCRIPT_PATH")
if echo "$FIRST_LINE" | grep -qE '^#!/(usr/)?bin/(env )?bash'; then
  vf_pass "valid bash shebang"
else
  vf_fail "missing or invalid shebang (expected #!/bin/bash or #!/usr/bin/env bash)"
fi

# --- Hook Interface ---
vf_section "Hook Interface"

# Check for stdin consumption (hook_init or cat)
if echo "$CONTENT" | grep -qE 'hook_init|INPUT=\$\(cat'; then
  vf_pass "stdin consumed (hook_init or cat)"
  # Check stdin is consumed early (within first 20 lines)
  STDIN_LINE=$(echo "$CONTENT" | grep -nE 'hook_init|INPUT=\$\(cat' | head -1 | cut -d: -f1)
  if [ -n "$STDIN_LINE" ] && [ "$STDIN_LINE" -le 20 ]; then
    vf_pass "stdin consumed early (line $STDIN_LINE)"
  else
    vf_warn "stdin consumed late (line ${STDIN_LINE:-?}) — should be in first 15-20 lines before any other I/O"
  fi
else
  vf_warn "no stdin consumption found — hooks receive JSON on stdin (use hook_init or INPUT=\$(cat))"
fi

# Check for sourcing hook-input.sh
if echo "$CONTENT" | grep -q 'lib/hook-input.sh'; then
  vf_pass "sources lib/hook-input.sh"
else
  vf_warn "does not source lib/hook-input.sh — consider using shared hook input parsing"
fi

# --- Exit Code Contract ---
vf_section "Exit Codes"

# Check for exit statements
EXIT_COUNT=$(echo "$CONTENT" | grep -cE '^\s*(exit|return) [0-2]' || true)
if [ "$EXIT_COUNT" -gt 0 ]; then
  vf_pass "explicit exit/return codes found ($EXIT_COUNT)"
else
  vf_warn "no explicit exit codes — hooks use 0=allow, 1=warn, 2=block"
fi

# Check for exit codes > 2 (non-standard)
BAD_EXITS=$(echo "$CONTENT" | grep -nE '^\s*exit [3-9]|^\s*exit [0-9]{2,}' || true)
if [ -n "$BAD_EXITS" ]; then
  vf_fail "non-standard exit codes found (only 0, 1, 2 are valid for hooks):"
  echo "    $BAD_EXITS"
else
  vf_pass "no non-standard exit codes"
fi

# --- Session & Worktree Safety ---
vf_section "Session & Worktree Safety"

# Check for PPID usage (should use session_id)
if echo "$CONTENT" | grep -qE '\$PPID|\$\{PPID\}'; then
  PPID_LINES=$(echo "$CONTENT" | grep -nE '\$PPID|\$\{PPID\}' | head -3)
  vf_warn "uses \$PPID — prefer get_session_id from lib/worktree.sh for session isolation:"
  echo "    $PPID_LINES"
else
  vf_pass "no PPID usage"
fi

# Check for bare $(pwd) usage
if echo "$CONTENT" | grep -qE '\$\(pwd\)'; then
  PWD_LINES=$(echo "$CONTENT" | grep -nE '\$\(pwd\)' | head -3)
  vf_warn "uses \$(pwd) — in worktrees this returns the worktree path, not repo root. Use get_repo_root or CWD from hook input:"
  echo "    $PWD_LINES"
else
  vf_pass "no bare \$(pwd) usage"
fi

# Check for bare git commands (without -C flag)
BARE_GIT=$(echo "$CONTENT" | grep -nE '^\s*(git |.*\$\(git )' | grep -vE -- '-C |rev-parse --git' | head -5 || true)
if [ -n "$BARE_GIT" ]; then
  vf_warn "bare git commands found (may fail in worktrees — use git -C \"\$CWD\"):"
  echo "    $BARE_GIT"
else
  vf_pass "no bare git commands (all use -C flag or worktree-safe patterns)"
fi

# --- Graceful Degradation ---
vf_section "Graceful Degradation"

# Check for unguarded external tool calls
UNGUARDED_NODE=$(echo "$CONTENT" | grep -nE '^\s*node ' | grep -v '2>/dev/null' | grep -v '|| true' | head -3 || true)
if [ -n "$UNGUARDED_NODE" ]; then
  vf_warn "unguarded node calls (add 2>/dev/null || true):"
  echo "    $UNGUARDED_NODE"
fi

UNGUARDED_SQLITE=$(echo "$CONTENT" | grep -nE '^\s*sqlite3 ' | grep -v '2>/dev/null' | grep -v '|| true' | head -3 || true)
if [ -n "$UNGUARDED_SQLITE" ]; then
  vf_warn "unguarded sqlite3 calls (add 2>/dev/null || true):"
  echo "    $UNGUARDED_SQLITE"
fi

# Check for command existence guards
if echo "$CONTENT" | grep -qE 'command -v|which '; then
  vf_pass "command existence checks found"
fi

# --- Performance ---
vf_section "Performance"

LINE_COUNT=$(wc -l < "$SCRIPT_PATH")
if [ "$LINE_COUNT" -gt 300 ]; then
  vf_warn "script is $LINE_COUNT lines — consider splitting into dispatcher + validators for maintainability"
fi

# Check for sleep calls (should not be in sync hooks)
if echo "$CONTENT" | grep -qE '^\s*sleep '; then
  vf_fail "sleep found — synchronous hooks must complete in <100ms"
fi

vf_summary
vf_exit
