#!/usr/bin/env bash
# download-grammars.sh — Ensure WASM grammars are available via tree-sitter-wasms npm package
# Usage: download-grammars.sh
# Idempotent — checks if the package is installed, installs if not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"

# Check if tree-sitter-wasms is installed
WASMS_DIR="${PACKAGE_DIR}/node_modules/tree-sitter-wasms/out"

if [ -d "$WASMS_DIR" ]; then
  count=$(find "$WASMS_DIR" -name "*.wasm" 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    echo "codebase-pilot: tree-sitter-wasms installed ($count grammars available)" >&2
    exit 0
  fi
fi

echo "codebase-pilot: installing tree-sitter-wasms..." >&2
cd "$PACKAGE_DIR"
npm install --save tree-sitter-wasms 2>&1 | tail -1 >&2

count=$(find "$WASMS_DIR" -name "*.wasm" 2>/dev/null | wc -l)
echo "codebase-pilot: tree-sitter-wasms installed ($count grammars available)" >&2
