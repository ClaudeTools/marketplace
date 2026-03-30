#!/usr/bin/env bash
# validate-skill.sh — Check a skill directory follows Claude Code best practices
# Usage: bash validate-skill.sh /path/to/skill-directory
set -euo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ] || [ ! -d "$SKILL_DIR" ]; then
  echo "Usage: bash validate-skill.sh /path/to/skill-directory"
  exit 1
fi

# shellcheck source=lib/validator-framework.sh
source "$(dirname "$0")/lib/validator-framework.sh"

SKILL_MD="$SKILL_DIR/SKILL.md"
DIRNAME=$(basename "$SKILL_DIR")

echo "=== Validating skill: $DIRNAME ==="
echo ""

# --- SKILL.md existence ---
vf_section "Structure"
if [ ! -f "$SKILL_MD" ]; then
  vf_fail "SKILL.md not found in $SKILL_DIR"
  vf_summary
  vf_exit
fi
vf_pass "SKILL.md exists"

# --- Frontmatter ---
vf_section "Frontmatter"

# Check for YAML frontmatter delimiters
if head -1 "$SKILL_MD" | grep -q '^---$'; then
  vf_pass "frontmatter opening delimiter found"
else
  vf_fail "missing YAML frontmatter (file must start with ---)"
fi

# Extract frontmatter (between first two --- lines)
FRONTMATTER=$(sed -n '2,/^---$/p' "$SKILL_MD" | sed '$d')

# Check name field
NAME=$(echo "$FRONTMATTER" | grep -oP '^name:\s*\K.*' | tr -d ' ' || true)
if [ -n "$NAME" ]; then
  vf_pass "name field present: $NAME"
  if [ "$NAME" = "$DIRNAME" ]; then
    vf_pass "name matches directory name"
  else
    vf_fail "name '$NAME' does not match directory name '$DIRNAME'"
  fi
else
  vf_fail "missing 'name' field in frontmatter"
fi

# Check description field
DESC=$(echo "$FRONTMATTER" | grep -oP '^description:\s*\K.*' || true)
if [ -n "$DESC" ]; then
  DESC_LEN=${#DESC}
  vf_pass "description field present ($DESC_LEN chars)"
  if [ "$DESC_LEN" -lt 50 ]; then
    vf_warn "description is short ($DESC_LEN chars) — aim for 80-200 for better trigger accuracy"
  fi
  # Check for action verbs
  if echo "$DESC" | grep -qiE '\buse when\b|\buse for\b|\binvoke\b|\btrigger\b'; then
    vf_pass "description includes trigger context (Use when/Use for)"
  else
    vf_warn "description lacks trigger context — add 'Use when...' for better skill selection"
  fi
else
  vf_fail "missing 'description' field in frontmatter"
fi

# --- Size limits ---
vf_section "Size"

LINE_COUNT=$(wc -l < "$SKILL_MD")
if [ "$LINE_COUNT" -le 500 ]; then
  vf_pass "SKILL.md is $LINE_COUNT lines (limit: 500)"
else
  vf_fail "SKILL.md is $LINE_COUNT lines — exceeds 500-line limit. Move content to references/"
fi

# --- Resource architecture ---
vf_section "Resources"

if [ -d "$SKILL_DIR/references" ]; then
  REF_COUNT=$(find "$SKILL_DIR/references" -name "*.md" 2>/dev/null | wc -l)
  vf_pass "references/ directory exists ($REF_COUNT files)"
  # Check reference sizes
  while IFS= read -r ref; do
    REF_LINES=$(wc -l < "$ref")
    REF_NAME=$(basename "$ref")
    if [ "$REF_LINES" -gt 400 ]; then
      vf_warn "$REF_NAME is $REF_LINES lines — consider splitting (target: 150-400)"
    fi
  done < <(find "$SKILL_DIR/references" -name "*.md" 2>/dev/null)
else
  if [ "$LINE_COUNT" -gt 200 ]; then
    vf_warn "no references/ directory — consider splitting content for skills over 200 lines"
  fi
fi

if [ -d "$SKILL_DIR/scripts" ]; then
  SCRIPT_COUNT=$(find "$SKILL_DIR/scripts" -name "*.sh" 2>/dev/null | wc -l)
  vf_pass "scripts/ directory exists ($SCRIPT_COUNT files)"
  # Syntax check all scripts
  while IFS= read -r script; do
    SCRIPT_NAME=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
      vf_pass "$SCRIPT_NAME passes bash -n"
    else
      vf_fail "$SCRIPT_NAME fails bash -n syntax check"
    fi
  done < <(find "$SKILL_DIR/scripts" -name "*.sh" 2>/dev/null)
fi

# --- Content quality ---
vf_section "Content Quality"

# Check for conditional reference loading
if [ -d "$SKILL_DIR/references" ] && [ "$REF_COUNT" -gt 0 ]; then
  REFS_MENTIONED=$(grep -c 'references/' "$SKILL_MD" || true)
  if [ "$REFS_MENTIONED" -ge "$REF_COUNT" ]; then
    vf_pass "all $REF_COUNT reference files are mentioned in SKILL.md"
  else
    vf_warn "only $REFS_MENTIONED of $REF_COUNT reference files mentioned in SKILL.md"
  fi
fi

# Check for verification/checklist section
if grep -qiE 'verification|checklist' "$SKILL_MD"; then
  vf_pass "verification/checklist section found"
else
  vf_warn "no verification or checklist section — add one to guide completion checks"
fi

# Check for gotchas section
if grep -qiE 'gotcha|common mistake|pitfall|watch out' "$SKILL_MD"; then
  vf_pass "gotchas/pitfalls section found"
else
  vf_warn "no gotchas section — non-obvious facts prevent real mistakes"
fi

# Check for examples
EXAMPLE_COUNT=$(grep -ciE 'example|```' "$SKILL_MD" || true)
if [ "$EXAMPLE_COUNT" -ge 2 ]; then
  vf_pass "examples found ($EXAMPLE_COUNT occurrences)"
else
  vf_warn "few or no examples — examples are the strongest steering signal"
fi

# --- Cross-references ---
vf_section "Cross-References"

# Check that referenced files exist
while IFS= read -r ref_path; do
  FULL_PATH="$SKILL_DIR/$ref_path"
  if [ -f "$FULL_PATH" ]; then
    vf_pass "referenced file exists: $ref_path"
  else
    vf_fail "referenced file missing: $ref_path"
  fi
done < <(grep -oP 'references/[a-zA-Z0-9_-]+\.md' "$SKILL_MD" 2>/dev/null | sort -u)

vf_summary
vf_exit
