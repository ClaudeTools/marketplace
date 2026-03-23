#!/bin/bash
# docs-archive.sh — Move deprecated docs to docs/archive/
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
ARCHIVED=0

MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/docs/archive/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -type f 2>/dev/null || true)

if [ -z "$MD_FILES" ]; then
  echo "No documentation files found."
  exit 0
fi

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue

  # Check front matter for status: deprecated
  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  [ "$first_line" != "---" ] && continue

  fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)
  status=$(echo "$fm" | { grep '^status:' || true; } | head -1 | sed 's/^status:[[:space:]]*//')

  if [ "$status" = "deprecated" ]; then
    # Determine the docs/ parent directory for this file
    docs_dir=$(echo "$md_file" | sed 's|\(/docs/\).*|\1|')
    archive_dir="${docs_dir}archive"
    mkdir -p "$archive_dir"

    fname=$(basename "$md_file")
    mv "$md_file" "$archive_dir/$fname"
    echo "Archived: $md_file -> $archive_dir/$fname"
    ARCHIVED=$((ARCHIVED + 1))
  fi
done <<< "$MD_FILES"

if [ "$ARCHIVED" -gt 0 ]; then
  echo ""
  echo "Archived $ARCHIVED deprecated doc(s). Run /docs-manager reindex to update indexes."
else
  echo "No deprecated documents found to archive."
fi
