#!/usr/bin/env bash
# docs-archive.sh — Move deprecated docs to docs/archive/
# Usage: docs-archive.sh [--execute]
# Default: dry-run mode (reports what WOULD be archived)
# Pass --execute to actually move files
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
EXECUTE=false
CANDIDATES=0

if [ "${1:-}" = "--execute" ]; then
  EXECUTE=true
fi

MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/docs/archive/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -not -name "_template.md" \
  -type f 2>/dev/null || true)

if [ -z "$MD_FILES" ]; then
  echo "No documentation files found."
  exit 0
fi

ARCHIVE_LIST=""

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue

  # Check front matter for status: deprecated
  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  [ "$first_line" != "---" ] && continue

  fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)
  status=$(echo "$fm" | { grep '^status:' || true; } | head -1 | sed 's/^status:[[:space:]]*//')

  if [ "$status" = "deprecated" ]; then
    CANDIDATES=$((CANDIDATES + 1))
    rel_path="${md_file#"$PROJECT_ROOT"/}"

    # Preserve relative structure: docs/guides/setup.md → docs/archive/guides/setup.md
    docs_dir=$(echo "$md_file" | sed 's|\(/docs/\).*|\1|')
    sub_path="${md_file#"$docs_dir"}"
    archive_dir="${docs_dir}archive/$(dirname "$sub_path")"
    fname=$(basename "$md_file")

    if [ "$EXECUTE" = true ]; then
      mkdir -p "$archive_dir"
      mv "$md_file" "$archive_dir/$fname"
      echo "  Archived: $rel_path -> ${archive_dir#"$PROJECT_ROOT"/}/$fname"
    else
      ARCHIVE_LIST="${ARCHIVE_LIST}  ${rel_path}\n"
    fi
  fi
done <<< "$MD_FILES"

if [ "$CANDIDATES" -eq 0 ]; then
  echo "No deprecated documents found to archive."
  echo "To mark a doc for archiving, set 'status: deprecated' in its front matter."
  exit 0
fi

if [ "$EXECUTE" = true ]; then
  echo ""
  echo "Archived $CANDIDATES document(s). Run /docs-manager reindex to update indexes."
else
  echo "=== Archive Candidates (dry run) ==="
  echo "Found $CANDIDATES deprecated document(s):"
  echo ""
  echo -e "$ARCHIVE_LIST"
  echo "To archive these, run with --execute flag."
fi
