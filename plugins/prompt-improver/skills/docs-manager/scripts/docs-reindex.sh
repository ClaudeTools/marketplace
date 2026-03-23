#!/bin/bash
# docs-reindex.sh — Force-regenerate index.md for all docs/ directories
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
bash "$PLUGIN_ROOT/scripts/doc-index-generator.sh" < /dev/null
echo "Reindex complete."
