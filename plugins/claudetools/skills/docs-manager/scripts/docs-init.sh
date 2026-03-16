#!/bin/bash
# docs-init.sh — Create standard docs/ directory structure with front-matter templates
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
DOCS_ROOT="$PROJECT_ROOT/docs"
TODAY=$(date "+%Y-%m-%d")

create_index() {
  local dir="$1"
  local title="$2"
  cat > "$dir/index.md" <<EOF
---
title: ${title}
description: Index for ${title,,} documentation
updated: ${TODAY}
---

# ${title}

Documentation index — run \`/docs-manager reindex\` to regenerate.
EOF
}

# Create directory structure
mkdir -p "$DOCS_ROOT/guides"
mkdir -p "$DOCS_ROOT/reference"
mkdir -p "$DOCS_ROOT/decisions"

# Create index files
create_index "$DOCS_ROOT" "Documentation"
create_index "$DOCS_ROOT/guides" "Guides"
create_index "$DOCS_ROOT/reference" "Reference"
create_index "$DOCS_ROOT/decisions" "Decisions"

echo "Created docs/ structure at $DOCS_ROOT:"
echo "  docs/"
echo "    index.md"
echo "    guides/"
echo "      index.md"
echo "    reference/"
echo "      index.md"
echo "    decisions/"
echo "      index.md"
