#!/bin/bash
# SessionEnd async hook — regenerates index.md files in docs/ directories
# Finds all docs/ directories, reads front matter from .md files, and generates
# a table-of-contents index.md for each.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
hook_log "invoked"

# Determine project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# Find all docs/ directories
DOCS_DIRS=$(find "$PROJECT_ROOT" -type d -name "docs" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  2>/dev/null || true)

if [ -z "$DOCS_DIRS" ]; then
  hook_log "no docs/ directories found"
  exit 0
fi

while IFS= read -r docs_dir; do
  [ -z "$docs_dir" ] && continue
  hook_log "generating index for $docs_dir"

  # Collect entries: title|description|updated|filename
  ENTRIES=""
  while IFS= read -r md_file; do
    [ -z "$md_file" ] && continue
    fname=$(basename "$md_file")

    # Skip index.md itself
    [ "$fname" = "index.md" ] && continue

    # Read front matter
    first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
    if [ "$first_line" = "---" ]; then
      fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)
      title=$(echo "$fm" | { grep '^title:' || true; } | head -1 | sed 's/^title:[[:space:]]*//')
      description=$(echo "$fm" | { grep '^description:' || true; } | head -1 | sed 's/^description:[[:space:]]*//')
      updated=$(echo "$fm" | { grep '^updated:' || true; } | head -1 | sed 's/^updated:[[:space:]]*//')
    else
      title="$fname"
      description=""
      updated=""
    fi

    # Default title to filename if empty
    [ -z "$title" ] && title="$fname"

    ENTRIES="${ENTRIES}${title}|${description}|${updated}|${fname}\n"
  done < <(find "$docs_dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)

  # Sort entries alphabetically by title
  SORTED=$(echo -e "$ENTRIES" | sort -t'|' -k1,1 -f | sed '/^$/d')

  # Generate index.md
  INDEX_FILE="$docs_dir/index.md"
  {
    echo "# Documentation Index"
    echo ""
    echo "| Document | Description | Last Updated |"
    echo "|----------|-------------|--------------|"
    while IFS='|' read -r title desc updated fname; do
      [ -z "$title" ] && continue
      echo "| [${title}](${fname}) | ${desc} | ${updated} |"
    done <<< "$SORTED"
  } > "$INDEX_FILE"

  hook_log "wrote index: $INDEX_FILE"
done <<< "$DOCS_DIRS"

exit 0
