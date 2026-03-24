#!/bin/bash
# Generate CSS design tokens (globals.css) from color inputs
# Usage: generate-tokens.sh --brand "#hex" --bg "#hex" --fg "#hex" [--accent "#hex"] [--radius sm|md|lg]
# Or pipe a design brief: cat brief.md | generate-tokens.sh --from-brief

set -euo pipefail

BRAND=""
BG=""
FG=""
ACCENT=""
RADIUS="md"
FROM_BRIEF=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --brand) BRAND="$2"; shift 2 ;;
    --bg) BG="$2"; shift 2 ;;
    --fg) FG="$2"; shift 2 ;;
    --accent) ACCENT="$2"; shift 2 ;;
    --radius) RADIUS="$2"; shift 2 ;;
    --from-brief) FROM_BRIEF=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# If reading from brief, extract colors
if [ "$FROM_BRIEF" = true ]; then
  BRIEF=$(cat)
  BRAND=$(echo "$BRIEF" | grep -i "brand" | grep -oE '#[0-9a-fA-F]{6}' | head -1 || true)
  BG=$(echo "$BRIEF" | grep -i "background" | grep -oE '#[0-9a-fA-F]{6}' | head -1 || true)
  FG=$(echo "$BRIEF" | grep -i "foreground" | grep -oE '#[0-9a-fA-F]{6}' | head -1 || true)
  ACCENT=$(echo "$BRIEF" | grep -i "accent" | grep -oE '#[0-9a-fA-F]{6}' | head -1 || true)
fi

# Defaults if not provided
BRAND="${BRAND:-#3b82f6}"
BG="${BG:-#ffffff}"
FG="${FG:-#0a0a0a}"
ACCENT="${ACCENT:-$BRAND}"

case "$RADIUS" in
  sm) R_SM="0.25rem"; R_MD="0.375rem"; R_LG="0.5rem"; R_XL="0.75rem" ;;
  md) R_SM="0.375rem"; R_MD="0.5rem"; R_LG="0.75rem"; R_XL="1rem" ;;
  lg) R_SM="0.5rem"; R_MD="0.75rem"; R_LG="1rem"; R_XL="1.5rem" ;;
  *) R_SM="0.375rem"; R_MD="0.5rem"; R_LG="0.75rem"; R_XL="1rem" ;;
esac

cat <<TOKENS
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    /* Background hierarchy */
    --background: ${BG};
    --background-subtle: color-mix(in srgb, ${BG} 95%, ${FG});
    --background-muted: color-mix(in srgb, ${BG} 90%, ${FG});
    --background-emphasis: color-mix(in srgb, ${BG} 85%, ${FG});

    /* Foreground hierarchy */
    --foreground: ${FG};
    --foreground-secondary: color-mix(in srgb, ${FG} 70%, ${BG});
    --foreground-tertiary: color-mix(in srgb, ${FG} 50%, ${BG});
    --foreground-muted: color-mix(in srgb, ${FG} 35%, ${BG});

    /* Border hierarchy */
    --border: color-mix(in srgb, ${FG} 10%, ${BG});
    --border-subtle: color-mix(in srgb, ${FG} 6%, ${BG});
    --border-strong: color-mix(in srgb, ${FG} 15%, ${BG});
    --border-stronger: color-mix(in srgb, ${FG} 25%, ${BG});

    /* Brand */
    --brand: ${BRAND};
    --brand-foreground: ${BG};
    --brand-muted: color-mix(in srgb, ${BRAND} 15%, ${BG});

    /* Accent */
    --accent: ${ACCENT};
    --accent-foreground: ${BG};

    /* Semantic */
    --destructive: #ef4444;
    --destructive-foreground: #ffffff;
    --warning: #f59e0b;
    --warning-foreground: #0a0a0a;
    --success: #22c55e;
    --success-foreground: #ffffff;

    /* Controls */
    --control-bg: color-mix(in srgb, ${FG} 4%, ${BG});
    --control-border: color-mix(in srgb, ${FG} 12%, ${BG});
    --control-focus: ${BRAND};

    /* Radius scale */
    --radius-sm: ${R_SM};
    --radius: ${R_MD};
    --radius-lg: ${R_LG};
    --radius-xl: ${R_XL};
  }

  .dark {
    --background: ${FG};
    --background-subtle: color-mix(in srgb, ${FG} 95%, ${BG});
    --background-muted: color-mix(in srgb, ${FG} 90%, ${BG});
    --background-emphasis: color-mix(in srgb, ${FG} 85%, ${BG});

    --foreground: ${BG};
    --foreground-secondary: color-mix(in srgb, ${BG} 70%, ${FG});
    --foreground-tertiary: color-mix(in srgb, ${BG} 50%, ${FG});
    --foreground-muted: color-mix(in srgb, ${BG} 35%, ${FG});

    --border: color-mix(in srgb, ${BG} 10%, ${FG});
    --border-subtle: color-mix(in srgb, ${BG} 6%, ${FG});
    --border-strong: color-mix(in srgb, ${BG} 15%, ${FG});
    --border-stronger: color-mix(in srgb, ${BG} 25%, ${FG});

    --brand-muted: color-mix(in srgb, ${BRAND} 15%, ${FG});

    --control-bg: color-mix(in srgb, ${BG} 4%, ${FG});
    --control-border: color-mix(in srgb, ${BG} 12%, ${FG});
  }
}

@layer base {
  * {
    border-color: var(--border);
  }
  body {
    background-color: var(--background);
    color: var(--foreground);
  }
}
TOKENS
