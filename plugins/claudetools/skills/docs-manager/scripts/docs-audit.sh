#!/usr/bin/env bash
# docs-audit.sh — Scan all docs/ directories for quality issues
# Usage: docs-audit.sh [project-root]
# Output: Structured audit report with severity levels (ERROR, WARNING, INFO)
#
# Validates against industry-standard frontmatter schema:
#   Required: title, description, updated
#   Recommended: status, author, type, tags
#
# Severity levels:
#   ERROR   — broken or missing required data (must fix)
#   WARNING — quality issues that degrade docs (should fix)
#   INFO    — best-practice suggestions (nice to have)
set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
NOW_TS=$(date "+%s")
STALE_THRESHOLD_DAYS=90
TOTAL=0
ERRORS=0
WARNINGS=0
INFOS=0
REPORT=""

# Valid values for controlled fields
VALID_STATUSES="draft active review deprecated"
VALID_TYPES="guide reference decision tutorial overview changelog api runbook"

MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/docs/archive/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -not -name "_template.md" \
  -type f 2>/dev/null | sort || true)

if [ -z "$MD_FILES" ]; then
  echo "No documentation files found in docs/ directories."
  exit 0
fi

add_issue() {
  local severity="$1" msg="$2"
  case "$severity" in
    ERROR)   ERRORS=$((ERRORS + 1)) ;;
    WARNING) WARNINGS=$((WARNINGS + 1)) ;;
    INFO)    INFOS=$((INFOS + 1)) ;;
  esac
  file_issues="${file_issues}  ${severity}: ${msg}\n"
}

# Cross-platform date-to-epoch conversion
date_to_epoch() {
  local datestr="$1"
  date -d "$datestr" "+%s" 2>/dev/null \
    || date -j -f "%Y-%m-%d" "$datestr" "+%s" 2>/dev/null \
    || echo 0
}

# Extract a frontmatter field value
fm_field() {
  local fm="$1" field="$2"
  echo "$fm" | { grep "^${field}:" || true; } | head -1 | sed "s/^${field}:[[:space:]]*//"
}

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue
  TOTAL=$((TOTAL + 1))
  fname=$(basename "$md_file")
  rel_path="${md_file#"$PROJECT_ROOT"/}"
  file_issues=""

  # --- File-level checks ---

  # Empty file
  if [ ! -s "$md_file" ]; then
    add_issue "ERROR" "File has no content"
  fi

  # Kebab-case naming
  if [[ ! "$fname" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
    add_issue "INFO" "Filename '${fname}' is not kebab-case"
  fi

  # --- Frontmatter checks ---

  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  if [ "$first_line" != "---" ]; then
    add_issue "ERROR" "Missing YAML front matter"
  else
    fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)

    # --- Required fields ---

    title=$(fm_field "$fm" "title")
    description=$(fm_field "$fm" "description")
    updated=$(fm_field "$fm" "updated")

    # title
    if [ -z "$title" ]; then
      add_issue "ERROR" "Missing 'title' in front matter"
    else
      case "$title" in
        Untitled|Document|TODO|Draft|Title|"Document Title"|"New Document"|"")
          add_issue "WARNING" "Title '${title}' is generic — use a descriptive title"
          ;;
      esac
    fi

    # description
    if [ -z "$description" ]; then
      add_issue "ERROR" "Missing 'description' in front matter"
    elif [ "${#description}" -lt 10 ]; then
      add_issue "WARNING" "Description is too short (${#description} chars) — aim for a meaningful one-line summary"
    fi

    # updated
    if [ -z "$updated" ]; then
      add_issue "WARNING" "Missing 'updated' date — add updated: YYYY-MM-DD"
    elif [[ "$updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      updated_ts=$(date_to_epoch "$updated")
      if [ "$updated_ts" -gt 0 ]; then
        # Future date check
        if [ "$updated_ts" -gt "$NOW_TS" ]; then
          add_issue "WARNING" "Date '${updated}' is in the future"
        fi
        # Stale check
        days_old=$(( (NOW_TS - updated_ts) / 86400 ))
        if [ "$days_old" -gt "$STALE_THRESHOLD_DAYS" ]; then
          add_issue "WARNING" "Last updated ${days_old} days ago (${updated}) — threshold is ${STALE_THRESHOLD_DAYS} days"
        fi
      fi
    else
      add_issue "WARNING" "Date '${updated}' is not ISO format — use YYYY-MM-DD"
    fi

    # --- Recommended fields ---

    status=$(fm_field "$fm" "status")
    author=$(fm_field "$fm" "author")
    doc_type=$(fm_field "$fm" "type")
    has_tags=$(echo "$fm" | grep -c '^tags:' || true)

    # status — validate against allowed values
    if [ -z "$status" ]; then
      add_issue "INFO" "Missing 'status' — add status: draft|active|review|deprecated"
    else
      is_valid=false
      for valid in $VALID_STATUSES; do
        [ "$status" = "$valid" ] && is_valid=true
      done
      if [ "$is_valid" = false ]; then
        add_issue "WARNING" "Invalid status '${status}' — use one of: ${VALID_STATUSES}"
      fi
    fi

    # author
    if [ -z "$author" ]; then
      add_issue "INFO" "Missing 'author' — add author: name for maintenance tracking"
    fi

    # type — validate against allowed values
    if [ -z "$doc_type" ]; then
      add_issue "INFO" "Missing 'type' — add type: guide|reference|decision|tutorial|overview|changelog|api|runbook"
    else
      is_valid=false
      for valid in $VALID_TYPES; do
        [ "$doc_type" = "$valid" ] && is_valid=true
      done
      if [ "$is_valid" = false ]; then
        add_issue "INFO" "Unknown type '${doc_type}' — standard types: ${VALID_TYPES}"
      fi
    fi

    # tags
    if [ "$has_tags" -eq 0 ]; then
      add_issue "INFO" "Missing 'tags' — add tags: [keyword1, keyword2] for categorization"
    fi
  fi

  if [ -n "$file_issues" ]; then
    REPORT="${REPORT}${rel_path}:\n${file_issues}\n"
  fi
done <<< "$MD_FILES"

# --- Summary ---
echo "=== Documentation Audit ==="
echo "Scanned: $TOTAL files"
echo "Errors: $ERRORS | Warnings: $WARNINGS | Info: $INFOS"
echo ""

if [ -n "$REPORT" ]; then
  echo -e "$REPORT"
  echo "---"
  echo "Required fields: title, description, updated"
  echo "Recommended fields: status, author, type, tags"
  echo "See /docs-manager audit for interactive fixes."
else
  echo "All documentation passes quality checks."
fi
