#!/usr/bin/env bash
# docs-init.sh — Create standard docs/ directory structure with front-matter templates
# Usage: docs-init.sh [custom-subdirs]
# Example: docs-init.sh "api tutorials decisions"
# If no argument, creates: guides/ reference/ decisions/
#
# Templates follow industry-standard frontmatter schema:
#   Required: title, description, updated
#   Recommended: status, author, type, tags
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
DOCS_ROOT="$PROJECT_ROOT/docs"
TODAY=$(date "+%Y-%m-%d")

# Detect git user for author field
AUTHOR=$(git config user.name 2>/dev/null || echo "")

# Check if docs/ already exists
if [ -d "$DOCS_ROOT" ]; then
  echo "=== Existing docs/ structure ==="
  existing=$(find "$DOCS_ROOT" -type d -not -path "*/.git/*" | sort)
  echo "$existing" | sed "s|$PROJECT_ROOT/||"
  echo ""
  file_count=$(find "$DOCS_ROOT" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "Contains $file_count markdown files."
  echo ""
  echo "Proceeding to create any missing directories..."
fi

# Parse subdirectories from argument or use defaults
if [ $# -gt 0 ] && [ -n "$1" ]; then
  IFS=' ' read -ra SUBDIRS <<< "$1"
else
  SUBDIRS=(guides reference decisions)
fi

# Map subdirectory names to document types
type_for_subdir() {
  case "$1" in
    guides|tutorials) echo "guide" ;;
    reference|api)    echo "reference" ;;
    decisions)        echo "decision" ;;
    changelog*)       echo "changelog" ;;
    runbook*)         echo "runbook" ;;
    *)                echo "overview" ;;
  esac
}

create_index() {
  local dir="$1"
  local title="$2"
  local index_file="$dir/index.md"

  # Don't overwrite existing index files
  if [ -f "$index_file" ]; then
    echo "  Skipped: ${index_file#"$PROJECT_ROOT"/} (already exists)"
    return
  fi

  cat > "$index_file" <<EOF
---
title: ${title}
description: Index for ${title,,} documentation
updated: ${TODAY}
status: active
type: overview
---

# ${title}

Documentation index — run \`/docs-manager reindex\` to regenerate.
EOF
  echo "  Created: ${index_file#"$PROJECT_ROOT"/}"
}

create_template() {
  local dir="$1"
  local subdir_name="$2"
  local template_file="$dir/_template.md"
  local doc_type
  doc_type=$(type_for_subdir "$subdir_name")

  # Don't overwrite existing templates
  [ -f "$template_file" ] && return

  local author_line=""
  [ -n "$AUTHOR" ] && author_line="author: ${AUTHOR}"

  cat > "$template_file" <<EOF
---
title: Document Title
description: Brief description of what this document covers
updated: ${TODAY}
status: draft
type: ${doc_type}
${author_line}
tags: []
---

# Document Title

## Overview

What this document covers and why it matters.

## Content

Main content here.

---

*Frontmatter reference:*
- *title: Descriptive document title (required)*
- *description: One-line summary (required)*
- *updated: YYYY-MM-DD — last meaningful edit (required)*
- *status: draft | active | review | deprecated (recommended)*
- *type: guide | reference | decision | tutorial | overview | changelog | api | runbook (recommended)*
- *author: Who wrote or maintains this (recommended)*
- *tags: [keyword1, keyword2] for categorization (recommended)*
EOF
}

CREATED=0

# Create root docs/
mkdir -p "$DOCS_ROOT"
create_index "$DOCS_ROOT" "Documentation"

# Create subdirectories
for subdir in "${SUBDIRS[@]}"; do
  subdir_path="$DOCS_ROOT/$subdir"
  if [ ! -d "$subdir_path" ]; then
    mkdir -p "$subdir_path"
    CREATED=$((CREATED + 1))
  fi
  # Capitalize first letter for title
  title="$(tr '[:lower:]' '[:upper:]' <<< "${subdir:0:1}")${subdir:1}"
  create_index "$subdir_path" "$title"
  create_template "$subdir_path" "$subdir"
done

# Create archive directory
mkdir -p "$DOCS_ROOT/archive"

echo ""
echo "=== docs/ structure ==="
find "$DOCS_ROOT" -type d -not -path "*/.git/*" | sort | sed "s|$PROJECT_ROOT/||"
echo ""
echo "Created $CREATED new directories."
echo ""
echo "Frontmatter schema (per file):"
echo "  Required:    title, description, updated"
echo "  Recommended: status, author, type, tags"
echo ""
echo "Run /docs-manager audit to check quality."
