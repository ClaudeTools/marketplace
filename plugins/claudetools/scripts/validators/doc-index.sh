#!/bin/bash
# Validator: documentation index generator
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: (none — reads from git/PWD)
# Calls: hook_log
# Returns: 0 always (side-effect runner)

run_doc_index() {
  # Determine project root
  local PROJECT_ROOT
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

  # Find all docs/ directories
  local DOCS_DIRS
  DOCS_DIRS=$(find "$PROJECT_ROOT" -type d -name "docs" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/vendor/*" \
    2>/dev/null || true)

  if [ -z "$DOCS_DIRS" ]; then
    hook_log "no docs/ directories found"
    return 0
  fi

  while IFS= read -r docs_dir; do
    [ -z "$docs_dir" ] && continue
    hook_log "generating index for $docs_dir"

    # Collect entries: title|description|updated|filename
    local ENTRIES=""
    while IFS= read -r md_file; do
      [ -z "$md_file" ] && continue
      local fname
      fname=$(basename "$md_file")

      # Skip index.md itself
      [ "$fname" = "index.md" ] && continue

      # Read front matter
      local first_line
      first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
      local title description updated
      if [ "$first_line" = "---" ]; then
        local fm
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
    local SORTED
    SORTED=$(echo -e "$ENTRIES" | sort -t'|' -k1,1 -f | sed '/^$/d')

    # Generate index.md
    local INDEX_FILE="$docs_dir/index.md"
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

  return 0
}
