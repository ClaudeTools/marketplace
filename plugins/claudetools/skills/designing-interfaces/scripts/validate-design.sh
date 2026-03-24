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

# Check 1b: Dark mode token parity
if [ -n "$GLOBALS" ]; then
  if grep -q '\.dark' "$GLOBALS" 2>/dev/null; then
    ROOT_TOKENS=$(sed -n '/:root/,/}/p' "$GLOBALS" 2>/dev/null | grep -c '\-\-' || echo 0)
    DARK_TOKENS=$(sed -n '/\.dark/,/}/p' "$GLOBALS" 2>/dev/null | grep -c '\-\-' || echo 0)
    if [ "$ROOT_TOKENS" -eq "$DARK_TOKENS" ]; then
      check PASS "Dark mode tokens" ""
    else
      check WARN "Dark mode parity" ":root has $ROOT_TOKENS tokens but .dark has $DARK_TOKENS — missing overrides will fall back to light values"
    fi
  else
    check WARN "Dark mode" "No .dark block in globals.css — dark mode is not configured"
  fi
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

# Check 9: Responsive design patterns
# Check for mobile-first responsive classes (min-width breakpoints)
HAS_RESPONSIVE=0
RESPONSIVE_FILES=$(grep -rl 'sm:\|md:\|lg:\|xl:\|2xl:' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
RESPONSIVE_FILES=${RESPONSIVE_FILES:-0}

# Check for Container queries (modern responsive pattern)
CONTAINER_QUERIES=$(grep -rn '@container\|container-type' "$PROJECT_DIR" --include="*.css" --include="*.tsx" --include="*.jsx" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next 2>/dev/null | wc -l | tr -d '[:space:]')
CONTAINER_QUERIES=${CONTAINER_QUERIES:-0}

# Check for viewport meta tag
HAS_VIEWPORT=0
LAYOUT_FILES=$(find "$PROJECT_DIR" \( -name "layout.tsx" -o -name "layout.jsx" -o -name "index.html" -o -name "app.html" \) -not -path "*/node_modules/*" -not -path "*/.next/*" 2>/dev/null)
for lf in $LAYOUT_FILES; do
  if grep -q 'viewport' "$lf" 2>/dev/null; then
    HAS_VIEWPORT=1
    break
  fi
done

# Check for min-height: 100vh or min-h-screen (proper mobile viewport)
MOBILE_VH=$(grep -rn 'min-h-screen\|min-height:\s*100[svd]vh\|min-h-\[100[svd]vh\]' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.css" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next 2>/dev/null | wc -l | tr -d '[:space:]')
MOBILE_VH=${MOBILE_VH:-0}

# Check for touch target sizes (min 44px/48px)
SMALL_TOUCH=$(grep -rn 'w-6\b\|h-6\b\|w-5\b\|h-5\b\|w-4\b\|h-4\b' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next 2>/dev/null | grep -c 'button\|Button\|<a \|<Link\|onClick\|href' || echo 0)
SMALL_TOUCH=$(echo "$SMALL_TOUCH" | tr -d '[:space:]')
SMALL_TOUCH=${SMALL_TOUCH:-0}

# Report responsive findings
if [ "$RESPONSIVE_FILES" -gt 0 ]; then
  check PASS "Responsive breakpoints" ""
else
  check WARN "Responsive breakpoints" "No Tailwind responsive prefixes (sm: md: lg:) found — add responsive variants"
fi

if [ "$HAS_VIEWPORT" -eq 1 ]; then
  check PASS "Viewport meta" ""
else
  check WARN "Viewport meta" "No viewport meta tag found in layout — mobile scaling may be broken"
fi

if [ "$SMALL_TOUCH" -gt 3 ] 2>/dev/null; then
  check WARN "Touch targets" "$SMALL_TOUCH small interactive elements (w-4/5/6 on buttons/links) — ensure min 44px touch targets on mobile"
else
  check PASS "Touch targets" ""
fi

# Check 12: Focus outline removal without focus-visible replacement (WCAG 2.4.7)
# outline-none removes keyboard focus indicators — must be paired with focus-visible:ring or similar
OUTLINE_NONE_FILES=$(grep -rl 'outline-none\|outline:\s*none\|outline:\s*0' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.css" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null || true)
FOCUS_MISSING=0
if [ -n "$OUTLINE_NONE_FILES" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! grep -q 'focus-visible:\|focus:ring\|focus-visible:ring\|:focus-visible' "$f" 2>/dev/null; then
      FOCUS_MISSING=$((FOCUS_MISSING + 1))
    fi
  done <<< "$OUTLINE_NONE_FILES"
fi
if [ "$FOCUS_MISSING" -gt 0 ] 2>/dev/null; then
  check WARN "Focus indicators" "$FOCUS_MISSING file(s) remove outline without focus-visible replacement — keyboard users lose focus visibility (WCAG 2.4.7)"
else
  check PASS "Focus indicators" ""
fi

# Check 13: Multiple h1 tags (SEO + accessibility)
H1_COUNT=$(grep -rn '<h1\b\|<Heading.*level.*1\|<Typography.*variant.*h1' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
H1_COUNT=${H1_COUNT:-0}
if [ "$H1_COUNT" -gt 3 ] 2>/dev/null; then
  check WARN "Heading hierarchy" "$H1_COUNT <h1> tags across project — most pages should have exactly one h1"
else
  check PASS "Heading hierarchy" ""
fi

# Check 14: Images without width/height (Cumulative Layout Shift)
IMG_NO_DIMS=$(grep -rn '<img\b' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte" --include="*.astro" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | grep -v 'width=\|height=\|fill\b\|<Image\b' | wc -l | tr -d '[:space:]')
IMG_NO_DIMS=${IMG_NO_DIMS:-0}
if [ "$IMG_NO_DIMS" -gt 0 ] 2>/dev/null; then
  check WARN "Image dimensions" "$IMG_NO_DIMS <img> tag(s) without width/height — causes layout shift (CLS)"
else
  check PASS "Image dimensions" ""
fi

# Check 15: Animations without prefers-reduced-motion (WCAG 2.3.3)
HAS_ANIMATIONS=$(grep -rn 'animate-\|transition-\|@keyframes\|animation:' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.css" --include="*.vue" --include="*.svelte" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
HAS_ANIMATIONS=${HAS_ANIMATIONS:-0}
HAS_MOTION_QUERY=$(grep -rn 'prefers-reduced-motion\|motion-safe:\|motion-reduce:' "$PROJECT_DIR" --include="*.tsx" --include="*.jsx" --include="*.css" --include="*.vue" --include="*.svelte" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
HAS_MOTION_QUERY=${HAS_MOTION_QUERY:-0}
if [ "$HAS_ANIMATIONS" -gt 5 ] && [ "$HAS_MOTION_QUERY" -eq 0 ] 2>/dev/null; then
  check WARN "Motion accessibility" "$HAS_ANIMATIONS animation/transition uses but no prefers-reduced-motion support — add motion-safe: or @media query (WCAG 2.3.3)"
else
  check PASS "Motion accessibility" ""
fi

# Check 16: font-display in @font-face (FOIT/CLS prevention)
FONTFACE_COUNT=$(grep -rn '@font-face' "$PROJECT_DIR" --include="*.css" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
FONTFACE_COUNT=${FONTFACE_COUNT:-0}
FONT_DISPLAY_COUNT=$(grep -rn 'font-display' "$PROJECT_DIR" --include="*.css" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build --exclude-dir=out 2>/dev/null | wc -l | tr -d '[:space:]')
FONT_DISPLAY_COUNT=${FONT_DISPLAY_COUNT:-0}
if [ "$FONTFACE_COUNT" -gt 0 ] && [ "$FONT_DISPLAY_COUNT" -eq 0 ] 2>/dev/null; then
  check WARN "Font display" "$FONTFACE_COUNT @font-face without font-display: swap — causes Flash of Invisible Text"
elif [ "$FONTFACE_COUNT" -gt 0 ]; then
  check PASS "Font display" ""
fi

# Check 17: Icon-only links without accessible name (WCAG 2.4.4)
# Detect <a> or <Link> wrapping only an icon/svg/img without aria-label or sr-only text
ICON_LINKS=0
while IFS= read -r -d '' f; do
  count=$(grep -cE '<(a|Link)\b[^>]*>[[:space:]]*<(svg|img|Icon|[A-Z][a-zA-Z]*Icon)\b' "$f" 2>/dev/null || true)
  if [ "${count:-0}" -gt 0 ]; then
    # Check if these have aria-label
    no_label=$(grep -E '<(a|Link)\b[^>]*>[[:space:]]*<(svg|img|Icon|[A-Z][a-zA-Z]*Icon)\b' "$f" 2>/dev/null | grep -vc 'aria-label\|sr-only\|visually-hidden\|<span' || true)
    ICON_LINKS=$((ICON_LINKS + ${no_label:-0}))
  fi
done < <(find "$PROJECT_DIR" \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" \) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" -print0 2>/dev/null)
if [ "$ICON_LINKS" -gt 0 ] 2>/dev/null; then
  check WARN "Link accessibility" "$ICON_LINKS icon-only link(s) without aria-label or screen reader text (WCAG 2.4.4)"
else
  check PASS "Link accessibility" ""
fi

echo ""
echo "Summary: $PASS passed, $WARN warnings, $FAIL failures"
exit 0
