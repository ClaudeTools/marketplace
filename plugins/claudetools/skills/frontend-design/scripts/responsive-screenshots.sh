#!/bin/bash
# Capture screenshots at multiple responsive breakpoints.
# Two engines: Puppeteer (full features) or headless Chrome CLI (basic fallback).
#
# Usage:
#   responsive-screenshots.sh <url> [options]
#   responsive-screenshots.sh http://localhost:3000
#   responsive-screenshots.sh http://localhost:3000 --full-page --delay 3
#
# Features (Puppeteer engine):
#   - Full-page scroll capture (stitches entire page height)
#   - Disables sticky navs to prevent duplication
#   - Kills all animations/transitions for clean capture
#   - Scrolls page to trigger lazy-loaded images
#   - Dismisses common cookie banners
#   - Device emulation (mobile touch, user agent)
#   - Outputs metadata.json with page dimensions and fonts
#
# Breakpoints: mobile (390x844), tablet (768x1024), desktop (1440x900), wide (1920x1080)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPS_DIR="${SCRIPT_DIR}/.deps"

URL=""
OUTPUT_DIR="./screenshots"
DELAY=2
FULL_PAGE=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --delay) DELAY="$2"; shift 2 ;;
    --no-full-page) FULL_PAGE=false; shift ;;
    --full-page) FULL_PAGE=true; shift ;;
    --help|-h)
      echo "Usage: responsive-screenshots.sh <url> [options]"
      echo ""
      echo "Captures screenshots at 4 responsive breakpoints."
      echo "Uses Puppeteer for full features, falls back to headless Chrome CLI."
      echo ""
      echo "Options:"
      echo "  --output-dir <dir>   Output directory (default: ./screenshots)"
      echo "  --delay <seconds>    Wait for JS to render (default: 2)"
      echo "  --full-page          Capture full scroll height (default: on)"
      echo "  --no-full-page       Viewport-only capture"
      echo ""
      echo "Breakpoints:"
      echo "  mobile:   390x844   (iPhone 14 Pro, 3x DPR, touch)"
      echo "  tablet:   768x1024  (iPad portrait, 2x DPR, touch)"
      echo "  desktop:  1440x900  (Standard, 1x DPR)"
      echo "  wide:     1920x1080 (Full HD, 1x DPR)"
      echo ""
      echo "Puppeteer features (auto-installed on first run):"
      echo "  - Full page scroll capture with sticky nav handling"
      echo "  - Animation/transition freezing"
      echo "  - Lazy image triggering (scrolls entire page)"
      echo "  - Cookie banner auto-dismissal"
      echo "  - Per-breakpoint metadata (page height, fonts detected)"
      exit 0
      ;;
    *)
      if [ -z "$URL" ]; then
        URL="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$URL" ]; then
  echo "Usage: responsive-screenshots.sh <url> [--output-dir dir] [--delay 2]"
  echo "Run with --help for details."
  exit 1
fi

# --- Find Chrome/Chromium ---
CHROME=""
for cmd in google-chrome chromium chromium-browser; do
  if command -v "$cmd" &>/dev/null; then
    CHROME=$(command -v "$cmd")
    break
  fi
done
# macOS paths
if [ -z "$CHROME" ] && [ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi

if [ -z "$CHROME" ]; then
  echo "ERROR: Chrome/Chromium not found."
  echo "Install: sudo apt install chromium-browser (Linux) or brew install --cask google-chrome (macOS)"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# --- Try Puppeteer engine first (full features) ---
if command -v node &>/dev/null; then
  # Ensure puppeteer-core is installed in local deps dir
  if [ ! -d "$DEPS_DIR/node_modules/puppeteer-core" ]; then
    echo "Installing puppeteer-core (one-time, ~2MB)..."
    mkdir -p "$DEPS_DIR"
    echo '{"name":"screenshot-deps","private":true}' > "$DEPS_DIR/package.json"
    (cd "$DEPS_DIR" && npm install --silent puppeteer-core 2>/dev/null) || true
  fi

  if [ -d "$DEPS_DIR/node_modules/puppeteer-core" ]; then
    export CHROME_PATH="$CHROME"
    export OUTPUT_DIR
    export DELAY
    export FULL_PAGE
    export URL
    export NODE_PATH="$DEPS_DIR/node_modules"

    node "$SCRIPT_DIR/responsive-screenshots.mjs"
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 0 ]; then
      echo ""
      echo "Next steps:"
      echo "  Compare: bash $SCRIPT_DIR/screenshot-compare.sh reference.png ${OUTPUT_DIR}/desktop-1440x900.png"
      exit 0
    else
      echo "Puppeteer engine failed (exit $EXIT_CODE). Falling back to basic mode..."
    fi
  fi
fi

# --- Fallback: Basic headless Chrome CLI (viewport-only, no full page) ---
echo "Responsive Screenshots (Basic Mode — install Node.js for full features)"
echo "======================================================================="
echo "  URL: $URL"
echo "  Output: $OUTPUT_DIR/"
echo "  Note: Basic mode captures viewport only. Install Node.js for full-page scroll capture."
echo ""

BREAKPOINTS=("mobile:390:844" "tablet:768:1024" "desktop:1440:900" "wide:1920:1080")

for bp in "${BREAKPOINTS[@]}"; do
  IFS=':' read -r NAME WIDTH HEIGHT <<< "$bp"
  FILENAME="${OUTPUT_DIR}/${NAME}-${WIDTH}x${HEIGHT}.png"

  echo -n "  Capturing ${NAME} (${WIDTH}x${HEIGHT})... "

  CHROME_FLAGS=(
    --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage
    --hide-scrollbars "--window-size=${WIDTH},${HEIGHT}" "--screenshot=${FILENAME}"
  )
  [ "$DELAY" -gt 0 ] && CHROME_FLAGS+=("--virtual-time-budget=$((DELAY * 1000))")

  if "$CHROME" "${CHROME_FLAGS[@]}" "$URL" 2>/dev/null; then
    [ -f "$FILENAME" ] && echo "OK" || echo "FAILED"
  else
    echo "FAILED"
  fi
done

echo ""
echo "Screenshots saved to: $OUTPUT_DIR/"
exit 0
