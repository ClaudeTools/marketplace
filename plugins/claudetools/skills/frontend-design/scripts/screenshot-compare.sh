#!/bin/bash
# Compare two screenshots for design reproduction fidelity.
# Uses ImageMagick if available, falls back to dimension/size comparison.
#
# Usage:
#   screenshot-compare.sh <reference.png> <implementation.png> [--output diff.png]
#
# Output:
#   RMSE score (0 = identical), visual diff image, region analysis
#   Exit 0 always (informational)

set -euo pipefail

REFERENCE="${1:-}"
IMPLEMENTATION="${2:-}"
OUTPUT=""

# Parse optional args
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$REFERENCE" ] || [ -z "$IMPLEMENTATION" ]; then
  echo "Usage: screenshot-compare.sh <reference.png> <implementation.png> [--output diff.png]"
  echo ""
  echo "Compares two screenshots and reports design fidelity."
  echo "Requires ImageMagick for pixel-level diff (install: sudo apt install imagemagick)"
  echo "Without ImageMagick, reports basic dimension and file size comparison."
  exit 0
fi

if [ ! -f "$REFERENCE" ]; then
  echo "ERROR: Reference image not found: $REFERENCE"
  exit 1
fi

if [ ! -f "$IMPLEMENTATION" ]; then
  echo "ERROR: Implementation image not found: $IMPLEMENTATION"
  exit 1
fi

echo "Screenshot Comparison"
echo "====================="
echo "  Reference:      $REFERENCE"
echo "  Implementation: $IMPLEMENTATION"
echo ""

# Get dimensions
REF_DIMS=""
IMPL_DIMS=""
if command -v identify &>/dev/null; then
  REF_DIMS=$(identify -format "%wx%h" "$REFERENCE" 2>/dev/null || true)
  IMPL_DIMS=$(identify -format "%wx%h" "$IMPLEMENTATION" 2>/dev/null || true)
  echo "  Reference dimensions:      $REF_DIMS"
  echo "  Implementation dimensions: $IMPL_DIMS"
  if [ "$REF_DIMS" != "$IMPL_DIMS" ]; then
    echo "  WARNING: Dimensions differ! Resize implementation to match before comparing."
  fi
  echo ""
elif command -v file &>/dev/null; then
  echo "  Reference:      $(file "$REFERENCE" | grep -oE '[0-9]+ x [0-9]+' || echo 'unknown dims')"
  echo "  Implementation: $(file "$IMPLEMENTATION" | grep -oE '[0-9]+ x [0-9]+' || echo 'unknown dims')"
  echo ""
fi

# File size comparison (rough similarity indicator)
REF_SIZE=$(stat -c%s "$REFERENCE" 2>/dev/null || stat -f%z "$REFERENCE" 2>/dev/null || echo 0)
IMPL_SIZE=$(stat -c%s "$IMPLEMENTATION" 2>/dev/null || stat -f%z "$IMPLEMENTATION" 2>/dev/null || echo 0)
if [ "$REF_SIZE" -gt 0 ] && [ "$IMPL_SIZE" -gt 0 ]; then
  SIZE_RATIO=$(echo "scale=1; $IMPL_SIZE * 100 / $REF_SIZE" | bc 2>/dev/null || echo "?")
  echo "  File size ratio: ${SIZE_RATIO}% (100% = same complexity)"
fi

# ImageMagick pixel-level comparison
if command -v compare &>/dev/null; then
  echo ""
  echo "Pixel-Level Analysis (ImageMagick)"
  echo "-----------------------------------"

  # Set output path
  [ -z "$OUTPUT" ] && OUTPUT="/tmp/screenshot-diff-$(date +%s).png"

  # RMSE comparison (root mean square error)
  RMSE_OUTPUT=$(compare -metric RMSE "$REFERENCE" "$IMPLEMENTATION" "$OUTPUT" 2>&1 || true)
  RMSE_VALUE=$(echo "$RMSE_OUTPUT" | grep -oE '^[0-9.]+' || echo "N/A")
  RMSE_NORM=$(echo "$RMSE_OUTPUT" | grep -oE '\([0-9.]+\)' | tr -d '()' || echo "N/A")

  echo "  RMSE: $RMSE_VALUE (normalized: $RMSE_NORM)"
  echo "  Diff image: $OUTPUT"
  echo ""

  # Interpret the score
  if [ "$RMSE_NORM" != "N/A" ]; then
    # Normalized RMSE is 0-1 where 0 = identical
    SCORE=$(echo "scale=1; (1 - $RMSE_NORM) * 100" | bc 2>/dev/null || echo "?")
    echo "  Match score: ${SCORE}%"
    echo ""

    # Threshold guidance
    NORM_INT=$(echo "$RMSE_NORM * 100" | bc 2>/dev/null | cut -d. -f1 || echo 50)
    if [ "${NORM_INT:-50}" -lt 2 ]; then
      echo "  EXCELLENT: Near pixel-perfect match (<2% deviation)"
    elif [ "${NORM_INT:-50}" -lt 5 ]; then
      echo "  GOOD: Minor differences — likely spacing/font rendering"
    elif [ "${NORM_INT:-50}" -lt 10 ]; then
      echo "  FAIR: Noticeable differences — check colors, spacing, layout"
    elif [ "${NORM_INT:-50}" -lt 20 ]; then
      echo "  POOR: Significant differences — review the diff image"
    else
      echo "  LOW MATCH: Major structural differences"
    fi
  fi

  # Also generate AE (absolute error) diff for visual inspection
  AE_OUTPUT="${OUTPUT%.png}-highlight.png"
  compare -highlight-color red -lowlight-color none -compose src \
    "$REFERENCE" "$IMPLEMENTATION" "$AE_OUTPUT" 2>/dev/null || true
  if [ -f "$AE_OUTPUT" ]; then
    echo "  Highlight image: $AE_OUTPUT (red = different pixels)"
  fi

  # Region analysis: split into quadrants and compare each
  if command -v convert &>/dev/null && [ "$REF_DIMS" = "$IMPL_DIMS" ] && [ -n "$REF_DIMS" ]; then
    W=$(echo "$REF_DIMS" | cut -dx -f1)
    H=$(echo "$REF_DIMS" | cut -dx -f2)
    HW=$((W / 2))
    HH=$((H / 2))

    echo ""
    echo "  Region Analysis:"
    for region in "top-left:0x0+${HW}x${HH}" "top-right:${HW}x0+${HW}x${HH}" "bottom-left:0x${HH}+${HW}x${HH}" "bottom-right:${HW}x${HH}+${HW}x${HH}"; do
      NAME=$(echo "$region" | cut -d: -f1)
      GEOM=$(echo "$region" | cut -d: -f2)
      X=$(echo "$GEOM" | cut -dx -f1 | cut -d+ -f1)
      Y=$(echo "$GEOM" | cut -dx -f2 | cut -d+ -f1)

      # Crop both images and compare regions
      REF_CROP="/tmp/ref-${NAME}.png"
      IMPL_CROP="/tmp/impl-${NAME}.png"
      convert "$REFERENCE" -crop "${HW}x${HH}+${X}+${Y}" +repage "$REF_CROP" 2>/dev/null || continue
      convert "$IMPLEMENTATION" -crop "${HW}x${HH}+${X}+${Y}" +repage "$IMPL_CROP" 2>/dev/null || continue

      REGION_RMSE=$(compare -metric RMSE "$REF_CROP" "$IMPL_CROP" /dev/null 2>&1 || true)
      REGION_NORM=$(echo "$REGION_RMSE" | grep -oE '\([0-9.]+\)' | tr -d '()' || echo "N/A")
      if [ "$REGION_NORM" != "N/A" ]; then
        REGION_SCORE=$(echo "scale=1; (1 - $REGION_NORM) * 100" | bc 2>/dev/null || echo "?")
        echo "    ${NAME}: ${REGION_SCORE}% match"
      fi

      rm -f "$REF_CROP" "$IMPL_CROP" 2>/dev/null
    done
  fi

else
  echo ""
  echo "ImageMagick not found. Install for pixel-level comparison:"
  echo "  sudo apt install imagemagick    # Debian/Ubuntu"
  echo "  brew install imagemagick        # macOS"
  echo ""
  echo "Without ImageMagick, use the structured diff prompt in clone-workflow.md"
  echo "to compare visually via Chrome automation screenshots."
fi

echo ""
echo "Next steps:"
echo "  1. Open the diff image to see where differences are"
echo "  2. Fix the regions with lowest match scores"
echo "  3. Re-screenshot and re-compare until >93% overall match"
exit 0
