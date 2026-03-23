#!/bin/bash
# Validate design quality of a frontend project (framework-agnostic)
# Works with Next.js, Vite + React, Astro, SvelteKit, or any Tailwind-based project
# Usage: validate-design.sh [project-dir]
# Checks: color count, font count, accessibility, design tokens, component size, mobile-first

set -euo pipefail

PROJECT_DIR="${1:-.}"
PASS=0
WARN=0
FAIL=0

check() {
  local level="$1" name="$2" detail="$3"
  case "$level" in
    PASS) echo "  [PASS] $name"; PASS=$((PASS + 1)) ;;
    WARN) echo "  [WARN] $name: $detail"; WARN=$((WARN + 1)) ;;
    FAIL) echo "  [FAIL] $name: $detail"; FAIL=$((FAIL + 1)) ;;
  esac
}

echo "Design Validation: $PROJECT_DIR"
echo "================================"

# Check 1: Design tokens in globals.css
GLOBALS=$(find "$PROJECT_DIR" -name "globals.css" -not -path "*/node_modules/*" 2>/dev/null | head -1)
if [ -n "$GLOBALS" ]; then
  TOKEN_COUNT=$(grep -c '\-\-' "$GLOBALS" 2>/dev/null || echo 0)
  if [ "$TOKEN_COUNT" -gt 10 ]; then
    check PASS "Design tokens" ""
  elif [ "$TOKEN_COUNT" -gt 0 ]; then
    check WARN "Design tokens" "Only $TOKEN_COUNT CSS variables found — consider adding more semantic tokens"
  else
    check FAIL "Design tokens" "No CSS custom properties in globals.css — use semantic design tokens"
  fi

  # Check for raw colors in tsx files
  RAW_COLORS=0
  while IFS= read -r -d '' f; do
    count=$(grep -cE '(text-white|bg-white|bg-black|text-black|bg-gray-|text-gray-)' "$f" 2>/dev/null || true)
    RAW_COLORS=$((RAW_COLORS + count))
  done < <(find "$PROJECT_DIR" \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" \) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/.astro/*" -print0 2>/dev/null)
  if [ "$RAW_COLORS" -gt 3 ]; then
    check WARN "Raw colors" "$RAW_COLORS instances of raw Tailwind colors — use semantic tokens instead"
  else
    check PASS "Semantic colors" ""
  fi
else
  check WARN "Design tokens" "No globals.css found"
fi

# Check 2: Font count (distinct font families, not weight variants)
FONT_FAMILIES=""
# Extract distinct font-family values from CSS usage declarations only.
# @font-face blocks declare fonts but don't represent additional families in use.
# Use awk to skip any font-family: inside @font-face blocks.
CSS_FAMILIES=$(find "$PROJECT_DIR" -name "*.css" -not -path "*/node_modules/*" -print0 2>/dev/null | \
  xargs -0 awk '/@font-face/{ff=1} /\}/{if(ff) ff=0} !ff && /font-family:/{print}' 2>/dev/null | \
  sed -n "s/.*font-family:\s*['\"]\\?\([^;'\"]*\\).*/\\1/p" | tr ',' '\n' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u)
[ -n "$CSS_FAMILIES" ] && FONT_FAMILIES="$CSS_FAMILIES"
# Extract distinct next/font constructor names (e.g., Inter, Playfair_Display)
NEXT_FONTS=$(grep -roh "from ['\"]next/font/[^'\"]*['\"]" "$PROJECT_DIR" --include="*.tsx" --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules | sed "s/.*next\/font\/[a-z]*['\"]//;s/['\"]//g" | sort -u)
# Extract @fontsource package names
FONTSOURCE=$(grep -roh "@fontsource[a-z-]*/[a-z-]*" "$PROJECT_DIR" --include="*.tsx" --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules | sed 's/@fontsource[a-z-]*\///' | sort -u)
# Also extract import names: import { Inter, Roboto } from 'next/font/google'
NEXT_IMPORTS=$(grep -rhE "import\s*\{[^}]+\}\s*from\s*['\"]next/font" "$PROJECT_DIR" --include="*.tsx" --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules | sed "s/.*import\s*{\s*//;s/\s*}.*//" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u)
ALL_FONTS=$(printf '%s\n%s\n%s\n%s' "$CSS_FAMILIES" "$NEXT_FONTS" "$FONTSOURCE" "$NEXT_IMPORTS" | grep -v '^$' | grep -v 'sans-serif\|serif\|monospace\|system-ui\|inherit' | sort -u)
FONT_COUNT=$(echo "$ALL_FONTS" | grep -c . || echo 0)
FONT_COUNT=$(echo "$FONT_COUNT" | tr -d '[:space:]')
if [ "$FONT_COUNT" -le 2 ]; then
  check PASS "Font families" ""
elif [ "$FONT_COUNT" -le 3 ]; then
  check WARN "Font families" "$FONT_COUNT distinct font families — max 2 recommended"
else
  check FAIL "Font families" "$FONT_COUNT distinct font families — use max 2 font families"
fi

# Check 3: Accessibility - images without alt
MISSING_ALT=$(grep -rn '<img\b' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" 2>/dev/null | grep -v node_modules | grep -cv 'alt=' || echo 0)
MISSING_ALT=$(echo "$MISSING_ALT" | tr -d '[:space:]')
MISSING_ALT=${MISSING_ALT:-0}
if [ "$MISSING_ALT" -gt 0 ] 2>/dev/null; then
  check WARN "Image alt text" "$MISSING_ALT <img> tags without alt attribute"
else
  check PASS "Image alt text" ""
fi

# Check 4: Component size
LARGE_FILES=""
while IFS= read -r -d '' f; do
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  if [ "$lines" -gt 200 ]; then
    LARGE_FILES="${LARGE_FILES}$(basename "$f"):${lines}lines "
  fi
done < <(find "$PROJECT_DIR" \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" \) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/.astro/*" -print0 2>/dev/null)
if [ -n "$LARGE_FILES" ]; then
  check WARN "Component size" "Large files: $LARGE_FILES— split into smaller components"
else
  check PASS "Component size" ""
fi

# Check 5: space-* classes (anti-pattern)
SPACE_CLASSES=$(grep -rn 'space-[xy]-' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" 2>/dev/null | grep -vc node_modules || echo 0)
SPACE_CLASSES=$(echo "$SPACE_CLASSES" | tr -d '[:space:]')
SPACE_CLASSES=${SPACE_CLASSES:-0}
if [ "$SPACE_CLASSES" -gt 0 ] 2>/dev/null; then
  check WARN "Spacing" "$SPACE_CLASSES uses of space-* classes — prefer gap classes"
else
  check PASS "Spacing patterns" ""
fi

# Check 6: localStorage usage (exclude build output dirs)
LOCALSTORAGE=$(grep -rn 'localStorage' "$PROJECT_DIR" --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" --include="*.vue" --include="*.svelte" --include="*.astro" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out --exclude-dir=.svelte-kit --exclude-dir=.output --exclude-dir=.nuxt --exclude-dir=.vercel --exclude-dir=.turbo --exclude-dir=.cache --exclude-dir=.parcel-cache --exclude-dir=storybook-static 2>/dev/null | grep -vc '// *ignore\|\.test\.\|\.spec\.\|\.stories\.' || echo 0)
LOCALSTORAGE=$(echo "$LOCALSTORAGE" | tr -d '[:space:]')
LOCALSTORAGE=${LOCALSTORAGE:-0}
if [ "$LOCALSTORAGE" -gt 0 ] 2>/dev/null; then
  check WARN "localStorage" "$LOCALSTORAGE uses of localStorage — consider server-side persistence"
else
  check PASS "No localStorage" ""
fi

# Check 7: fetch inside useEffect (anti-pattern, exclude build output dirs)
FETCH_EFFECT=$(grep -rlP 'useEffect\s*\([^)]*\{[^}]*fetch\(' "$PROJECT_DIR" --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out --exclude-dir=.svelte-kit 2>/dev/null | wc -l | tr -d '[:space:]')
FETCH_EFFECT=${FETCH_EFFECT:-0}
if [ "$FETCH_EFFECT" -gt 0 ]; then
  check WARN "Data fetching" "fetch() inside useEffect detected in $FETCH_EFFECT file(s) — use SWR or pass data from RSC"
else
  check PASS "Data fetching" ""
fi

# Check 8: Emoji as icons (exclude build output dirs)
EMOJI_ICONS=$(grep -rPn '[\x{1F300}-\x{1F9FF}]' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out --exclude-dir=.svelte-kit 2>/dev/null | wc -l | tr -d '[:space:]')
EMOJI_ICONS=${EMOJI_ICONS:-0}
if [ "$EMOJI_ICONS" -gt 2 ]; then
  check WARN "Icons" "$EMOJI_ICONS potential emoji-as-icon uses — use Lucide or similar icon library"
else
  check PASS "Icon usage" ""
fi

echo ""
echo "Summary: $PASS passed, $WARN warnings, $FAIL failures"
exit 0
