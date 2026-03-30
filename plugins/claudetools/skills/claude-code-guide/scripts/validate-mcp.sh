#!/usr/bin/env bash
# validate-mcp.sh — Check an MCP server directory follows Claude Code best practices
# Usage: bash validate-mcp.sh /path/to/mcp-server-directory
set -euo pipefail

MCP_DIR="${1:-}"
if [ -z "$MCP_DIR" ] || [ ! -d "$MCP_DIR" ]; then
  echo "Usage: bash validate-mcp.sh /path/to/mcp-server-directory"
  exit 1
fi

# shellcheck source=lib/validator-framework.sh
source "$(dirname "$0")/lib/validator-framework.sh"

DIRNAME=$(basename "$MCP_DIR")

echo "=== Validating MCP server: $DIRNAME ==="
echo ""

# --- Structure ---
vf_section "Structure"

vf_pass "directory exists"

# Check for entry point
ENTRY_POINT=""
for candidate in server.js index.js server.mjs index.mjs; do
  if [ -f "$MCP_DIR/$candidate" ]; then
    ENTRY_POINT="$candidate"
    break
  fi
done

if [ -n "$ENTRY_POINT" ]; then
  vf_pass "entry point found: $ENTRY_POINT"
else
  vf_fail "no entry point found (expected server.js, index.js, server.mjs, or index.mjs)"
fi

# package.json
if [ -f "$MCP_DIR/package.json" ]; then
  vf_pass "package.json exists"
else
  vf_warn "no package.json — consider adding one for dependency management"
fi

# --- Bootstrap ---
vf_section "Bootstrap"

START_SH="$MCP_DIR/start.sh"
if [ -f "$START_SH" ]; then
  vf_pass "start.sh exists"
  if bash -n "$START_SH" 2>/dev/null; then
    vf_pass "start.sh passes bash -n syntax check"
  else
    vf_fail "start.sh fails bash -n syntax check"
  fi
else
  vf_fail "start.sh not found — MCP servers need a start script"
fi

# --- Dependencies ---
vf_section "Dependencies"

if [ -f "$MCP_DIR/package.json" ]; then
  if grep -q '@modelcontextprotocol/sdk' "$MCP_DIR/package.json" 2>/dev/null; then
    vf_pass "@modelcontextprotocol/sdk found in package.json"
  else
    vf_warn "@modelcontextprotocol/sdk not found in package.json — most MCP servers use the official SDK"
  fi
fi

# --- Safety ---
vf_section "Safety"

# Collect all .js and .mjs files for safety checks
JS_FILES=""
while IFS= read -r jsfile; do
  JS_FILES="$JS_FILES $jsfile"
done < <(find "$MCP_DIR" -maxdepth 3 -name "*.js" -o -name "*.mjs" 2>/dev/null | grep -v node_modules || true)

if [ -n "$JS_FILES" ]; then
  # Signal handling check
  if grep -rlE 'SIGPIPE|uncaughtException|SIGTERM|SIGINT' $JS_FILES >/dev/null 2>&1; then
    vf_pass "signal handling found in source files"
  else
    vf_warn "no signal handling detected — consider handling SIGTERM/SIGPIPE/uncaughtException for graceful shutdown"
  fi

  # External network calls check
  NETWORK_FILES=$(grep -rlE 'fetch\(|http\.get|https\.get|axios|node-fetch' $JS_FILES 2>/dev/null || true)
  if [ -n "$NETWORK_FILES" ]; then
    NETWORK_FILENAMES=""
    for nf in $NETWORK_FILES; do
      NETWORK_FILENAMES="$NETWORK_FILENAMES $(basename "$nf")"
    done
    vf_warn "external network calls detected in:$NETWORK_FILENAMES — MCP servers should typically be local-only"
  else
    vf_pass "no external network calls detected"
  fi
else
  vf_warn "no .js or .mjs files found to check for safety patterns"
fi

vf_summary
vf_exit
