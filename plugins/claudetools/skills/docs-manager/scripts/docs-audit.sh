#!/bin/bash
# docs-audit.sh — Scan all docs/ directories for quality issues
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
NOW_TS=$(date "+%s")
TOTAL=0
ISSUES=0
REPORT=""

MD_FILES=$(find "$PROJECT_ROOT" -path "*/docs/*.md" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -name "index.md" \
  -type f 2>/dev/null | sort || true)

if [ -z "$MD_FILES" ]; then
  echo "No documentation files found in docs/ directories."
  exit 0
fi

while IFS= read -r md_file; do
  [ -z "$md_file" ] && continue
  TOTAL=$((TOTAL + 1))
  fname=$(basename "$md_file")
  rel_path="${md_file#$PROJECT_ROOT/}"
  file_issues=""

  # Check: empty file
  if [ ! -s "$md_file" ]; then
    file_issues="${file_issues}  - EMPTY: file has no content\n"
  fi

  # Check: kebab-case naming
  if [[ ! "$fname" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
    file_issues="${file_issues}  - NAMING: '${fname}' is not kebab-case\n"
  fi

  # Check: front matter exists
  first_line=$(head -n 1 "$md_file" 2>/dev/null || true)
  if [ "$first_line" != "---" ]; then
    file_issues="${file_issues}  - FRONT MATTER: missing YAML front matter\n"
  else
    fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md_file" 2>/dev/null || true)

    # Check required fields
    has_title=$(echo "$fm" | grep -c '^title:' || true)
    has_desc=$(echo "$fm" | grep -c '^description:' || true)
    has_updated=$(echo "$fm" | grep -c '^updated:' || true)

    [ "$has_title" -eq 0 ] && file_issues="${file_issues}  - FIELD: missing 'title'\n"
    [ "$has_desc" -eq 0 ] && file_issues="${file_issues}  - FIELD: missing 'description'\n"
    [ "$has_updated" -eq 0 ] && file_issues="${file_issues}  - FIELD: missing 'updated'\n"

    # Check generic title
    if [ "$has_title" -gt 0 ]; then
      title=$(echo "$fm" | grep '^title:' | head -1 | sed 's/^title:[[:space:]]*//')
      case "$title" in
        Untitled|Document|TODO|Draft|"")
          file_issues="${file_issues}  - TITLE: '${title}' is generic\n"
          ;;
      esac
    fi

    # Check stale date
    if [ "$has_updated" -gt 0 ]; then
      updated=$(echo "$fm" | grep '^updated:' | head -1 | sed 's/^updated:[[:space:]]*//')
      if [[ "$updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        updated_ts=$(date -j -f "%Y-%m-%d" "$updated" "+%s" 2>/dev/null || date -d "$updated" "+%s" 2>/dev/null || echo 0)
        if [ "$updated_ts" -gt 0 ]; then
          days_old=$(( (NOW_TS - updated_ts) / 86400 ))
          if [ "$days_old" -gt 90 ]; then
            file_issues="${file_issues}  - STALE: last updated ${days_old} days ago (${updated})\n"
          fi
        fi
      fi
    fi
  fi

  if [ -n "$file_issues" ]; then
    ISSUES=$((ISSUES + 1))
    REPORT="${REPORT}${rel_path}:\n${file_issues}\n"
  fi
done <<< "$MD_FILES"

echo "=== Documentation Audit ==="
echo "Scanned: $TOTAL files"
echo "Issues: $ISSUES files with problems"
echo ""

if [ -n "$REPORT" ]; then
  echo -e "$REPORT"
else
  echo "All documentation passes quality checks."
fi
