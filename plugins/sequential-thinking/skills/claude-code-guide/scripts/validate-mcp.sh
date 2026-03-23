#!/usr/bin/env bash
# validate-mcp.sh — Check an MCP server directory follows Claude Code best practices
# Usage: bash validate-mcp.sh /path/to/mcp-server-directory
set -euo pipefail

MCP_DIR="${1:-}"
if [ -z "$MCP_DIR" ] || [ ! -d "$MCP_DIR" ]; then
  echo "Usage: bash validate-mcp.sh /path/to/mcp-server-directory"
  exit 1
fi

ERRORS=0
WARNINGS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

DIRNAME=$(basename "$MCP_DIR")

echo "=== Validating MCP server: $DIRNAME ==="
echo ""

# --- Structure ---
echo "--- Structure ---"

pass "directory exists"

# Check for entry point
ENTRY_POINT=""
for candidate in server.js index.js server.mjs index.mjs; do
  if [ -f "$MCP_DIR/$candidate" ]; then
    ENTRY_POINT="$candidate"
    break
  fi
done

if [ -n "$ENTRY_POINT" ]; then
  pass "entry point found: $ENTRY_POINT"
else
  fail "no entry point found (expected server.js, index.js, server.mjs, or index.mjs)"
fi

# package.json
if [ -f "$MCP_DIR/package.json" ]; then
  pass "package.json exists"
else
  warn "no package.json — consider adding one for dependency management"
fi

# --- Bootstrap ---
echo ""
echo "--- Bootstrap ---"

START_SH="$MCP_DIR/start.sh"
if [ -f "$START_SH" ]; then
  pass "start.sh exists"
  if bash -n "$START_SH" 2>/dev/null; then
    pass "start.sh passes bash -n syntax check"
  else
    fail "start.sh fails bash -n syntax check"
  fi
else
  fail "start.sh not found — MCP servers need a start script"
fi

# --- Dependencies ---
echo ""
echo "--- Dependencies ---"

if [ -f "$MCP_DIR/package.json" ]; then
  if grep -q '@modelcontextprotocol/sdk' "$MCP_DIR/package.json" 2>/dev/null; then
    pass "@modelcontextprotocol/sdk found in package.json"
  else
    warn "@modelcontextprotocol/sdk not found in package.json — most MCP servers use the official SDK"
  fi
fi

# --- Safety ---
echo ""
echo "--- Safety ---"

# Collect all .js and .mjs files for safety checks
JS_FILES=""
while IFS= read -r jsfile; do
  JS_FILES="$JS_FILES $jsfile"
done < <(find "$MCP_DIR" -maxdepth 3 -name "*.js" -o -name "*.mjs" 2>/dev/null | grep -v node_modules || true)

if [ -n "$JS_FILES" ]; then
  # Signal handling check
  if grep -rlE 'SIGPIPE|uncaughtException|SIGTERM|SIGINT' $JS_FILES >/dev/null 2>&1; then
    pass "signal handling found in source files"
  else
    warn "no signal handling detected — consider handling SIGTERM/SIGPIPE/uncaughtException for graceful shutdown"
  fi

  # External network calls check
  NETWORK_FILES=$(grep -rlE 'fetch\(|http\.get|https\.get|axios|node-fetch' $JS_FILES 2>/dev/null || true)
  if [ -n "$NETWORK_FILES" ]; then
    NETWORK_FILENAMES=""
    for nf in $NETWORK_FILES; do
      NETWORK_FILENAMES="$NETWORK_FILENAMES $(basename "$nf")"
    done
    warn "external network calls detected in:$NETWORK_FILENAMES — MCP servers should typically be local-only"
  else
    pass "no external network calls detected"
  fi
else
  warn "no .js or .mjs files found to check for safety patterns"
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
