#!/usr/bin/env bash
# docs-reindex.sh — Regenerate docs/index.md files from frontmatter
# Usage: docs-reindex.sh [project-root]
# Scans all docs/ directories (including subdirectories) and generates index.md tables
#
# Reads frontmatter fields: title, description, updated, type, status
# Generates markdown table with: Document | Type | Description | Last Updated
set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
UPDATED=0

# Find all docs/ directories (top-level docs dirs, not subdirectories of docs)
DOCS_ROOTS=$(find "$PROJECT_ROOT" -type d -name "docs" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -path "*/docs/archive/*" \
  -not -path "*/docs/*/docs/*" \
  2>/dev/null || true)

if [ -z "$DOCS_ROOTS" ]; then
  echo "No docs/ directories found."
  exit 0
fi

# Extract a frontmatter field value
fm_field() {
  local fm="$1" field="$2"
  echo "$fm" | { grep "^${field}:" || true; } | head -1 | sed "s/^${field}:[[:space:]]*//"
}

generate_index() {
  local target_dir="$1"
  local title="$2"

  # Collect entries: title|type|description|updated|status|filename
  local entries=""
  while IFS= read -r md_file; do
    [ -z "$md_file" ] && continue
    local fname
    fname=$(basename "$md_file")

    # Skip index.md and templates
    [ "$fname" = "index.md" ] && continue
    [ "$fname" = "_template.md" ] && continue

    local first_line
    first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
    local doc_title="" description="" updated="" doc_type="" status=""

    if [ "$first_line" = "---" ]; then
      local fm
      fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)
      doc_title=$(fm_field "$fm" "title")
      description=$(fm_field "$fm" "description")
      updated=$(fm_field "$fm" "updated")
      doc_type=$(fm_field "$fm" "type")
      status=$(fm_field "$fm" "status")
    fi

    # Skip deprecated docs from the main index
    [ "$status" = "deprecated" ] && continue

    [ -z "$doc_title" ] && doc_title="$fname"
    [ -z "$doc_type" ] && doc_type="-"
    entries="${entries}${doc_title}|${doc_type}|${description}|${updated}|${fname}\n"
  done < <(find "$target_dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)

  # Also list subdirectories (link to their index.md)
  while IFS= read -r subdir; do
    [ -z "$subdir" ] && continue
    local dirname
    dirname=$(basename "$subdir")
    [ "$dirname" = "archive" ] && continue

    local sub_index="$subdir/index.md"
    local sub_title="$dirname" sub_desc="" sub_updated=""
    if [ -f "$sub_index" ]; then
      local first_line
      first_line=$(head -n 1 "$sub_index" 2>/dev/null || true)
      if [ "$first_line" = "---" ]; then
        local fm
        fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$sub_index" 2>/dev/null || true)
        sub_title=$(fm_field "$fm" "title")
        sub_desc=$(fm_field "$fm" "description")
        sub_updated=$(fm_field "$fm" "updated")
      fi
      [ -z "$sub_title" ] && sub_title="$dirname"
      entries="${entries}${sub_title}|section|${sub_desc}|${sub_updated}|${dirname}/index.md\n"
    fi
  done < <(find "$target_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

  # Skip if no entries
  local sorted
  sorted=$(echo -e "$entries" | sort -t'|' -k1,1 -f | sed '/^$/d')
  if [ -z "$sorted" ]; then
    return
  fi

  # Write index
  local index_file="$target_dir/index.md"
  {
    echo "---"
    echo "title: ${title}"
    echo "description: Index for ${title,,} documentation"
    echo "updated: $(date '+%Y-%m-%d')"
    echo "status: active"
    echo "type: overview"
    echo "---"
    echo ""
    echo "# ${title}"
    echo ""
    echo "| Document | Type | Description | Updated |"
    echo "|----------|------|-------------|---------|"
    while IFS='|' read -r t dtype desc upd fname; do
      [ -z "$t" ] && continue
      echo "| [${t}](${fname}) | ${dtype} | ${desc} | ${upd} |"
    done <<< "$sorted"
  } > "$index_file"

  UPDATED=$((UPDATED + 1))
}

# Process each docs root and its subdirectories
while IFS= read -r docs_root; do
  [ -z "$docs_root" ] && continue

  root_title="Documentation"
  generate_index "$docs_root" "$root_title"

  # Generate indexes for each subdirectory
  while IFS= read -r subdir; do
    [ -z "$subdir" ] && continue
    dirname=$(basename "$subdir")
    [ "$dirname" = "archive" ] && continue
    sub_title="$(tr '[:lower:]' '[:upper:]' <<< "${dirname:0:1}")${dirname:1}"
    generate_index "$subdir" "$sub_title"
  done < <(find "$docs_root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

done <<< "$DOCS_ROOTS"

echo "Updated $UPDATED index file(s)."
if [ "$UPDATED" -gt 0 ]; then
  echo "Run 'git diff docs/' to see changes."
fi
