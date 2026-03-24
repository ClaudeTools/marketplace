#!/usr/bin/env python3
"""Design system generator — creates a complete globals.css from minimal inputs.

Usage:
  python3 design-system.py --brand "#3b82f6" --ratio 1.25 --grid 4
  python3 design-system.py --brand "#059669" --bg "#fefce8" --fg "#1c1917" --ratio golden --grid 8
  python3 design-system.py --theme midnight
  python3 design-system.py --theme forest --brand "#10b981"  # override brand color
  python3 design-system.py --list-themes
"""
import colorsys
import math
import sys
import json
import argparse

# Import sibling modules
import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

def load_theme(name):
    """Load a theme seed from theme-seeds.json."""
    seeds_path = os.path.join(SCRIPT_DIR, "..", "assets", "theme-seeds.json")
    if not os.path.exists(seeds_path):
        print(f"Theme seeds not found at {seeds_path}", file=sys.stderr)
        sys.exit(1)
    with open(seeds_path) as f:
        data = json.load(f)
    themes = data.get("themes", {})
    if name not in themes:
        print(f"Unknown theme: {name}", file=sys.stderr)
        print(f"Available: {', '.join(sorted(themes.keys()))}", file=sys.stderr)
        sys.exit(1)
    return themes[name]

def list_themes():
    """Print all available theme seeds."""
    seeds_path = os.path.join(SCRIPT_DIR, "..", "assets", "theme-seeds.json")
    if not os.path.exists(seeds_path):
        print("Theme seeds not found")
        sys.exit(1)
    with open(seeds_path) as f:
        data = json.load(f)
    themes = data.get("themes", {})
    print(f"Available themes ({len(themes)}):\n")
    for name, t in sorted(themes.items()):
        print(f"  {name:12s}  {t['brand']}  {t['temperature']:7s}  {t['depth']}")
        print(f"               {t['description']}")
        print()

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16)/255.0 for i in (0,2,4))

def rgb_to_hex(r,g,b):
    return '#{:02x}{:02x}{:02x}'.format(int(max(0,min(1,r))*255), int(max(0,min(1,g))*255), int(max(0,min(1,b))*255))

def hex_to_hsl(h):
    r,g,b = hex_to_rgb(h)
    hue,lig,sat = colorsys.rgb_to_hls(r,g,b)
    return (hue*360, sat*100, lig*100)

def hsl_to_hex(h,s,l):
    r,g,b = colorsys.hls_to_rgb(h/360, l/100, s/100)
    return rgb_to_hex(r,g,b)

def relative_luminance(hex_color):
    r,g,b = hex_to_rgb(hex_color)
    def lin(c): return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)

def contrast_ratio(c1,c2):
    l1,l2=relative_luminance(c1),relative_luminance(c2)
    return (max(l1,l2)+0.05)/(min(l1,l2)+0.05)

def to_hsl_css(hex_color):
    """Convert hex to CSS HSL space-separated format (shadcn convention)."""
    h, s, l = hex_to_hsl(hex_color)
    return f"{h:.0f} {s:.1f}% {l:.1f}%"

NAMED_RATIOS = {
    "minor-second":1.067, "major-second":1.125, "minor-third":1.200,
    "major-third":1.250, "perfect-fourth":1.333, "augmented-fourth":1.414,
    "perfect-fifth":1.500, "golden":1.618,
}

def snap(v, grid): return round(v/grid)*grid

def type_scale(base, ratio, grid):
    names = ["xs","sm","base","lg","xl","2xl","3xl","4xl"]
    sizes = {}
    for i in range(-2, 6):
        raw = base * (ratio ** i)
        snapped = snap(raw, grid)
        name = names[i+2] if i+2 < len(names) else f"step-{i+2}"
        lh_ratio = max(1.15, min(1.7, 1.5 - (snapped-12)*0.008))
        lh = snap(snapped * lh_ratio, grid)
        sizes[name] = {"size": snapped, "lh": lh}
    return sizes

def spacing_scale(grid):
    if grid == 4:
        return [1,2,3,4,5,6,8,10,12,16,20,24,32,40,48,64]
    elif grid == 8:
        return [4,8,12,16,24,32,40,48,56,64,80,96]
    else:
        return [grid*i for i in range(1,17)]

def generate(brand, bg, fg, ratio_val, grid, radius, theme_extras=None):
    bh, bs, bl = hex_to_hsl(brand)

    # --- Light mode surfaces ---
    bg_h, bg_s, bg_l = hex_to_hsl(bg)
    fg_h, fg_s, fg_l = hex_to_hsl(fg)

    light = {
        "background": bg,
        "background-subtle": hsl_to_hex(bg_h, bg_s*0.5, max(bg_l-3, 0)),
        "background-muted": hsl_to_hex(bg_h, bg_s*0.4, max(bg_l-5, 0)),
        "background-emphasis": hsl_to_hex(bg_h, bg_s*0.3, max(bg_l-8, 0)),
        "foreground": fg,
        "foreground-secondary": hsl_to_hex(fg_h, fg_s*0.6, min(fg_l+20, 45)),
        "foreground-tertiary": hsl_to_hex(fg_h, fg_s*0.4, min(fg_l+35, 55)),
        "foreground-muted": hsl_to_hex(fg_h, fg_s*0.3, min(fg_l+50, 70)),
        "border": hsl_to_hex(fg_h, fg_s*0.1, min(fg_l+80, 90)),
        "border-subtle": hsl_to_hex(fg_h, fg_s*0.05, min(fg_l+85, 94)),
        "border-strong": hsl_to_hex(fg_h, fg_s*0.15, min(fg_l+70, 82)),
        "border-stronger": hsl_to_hex(fg_h, fg_s*0.2, min(fg_l+55, 70)),
        "brand": brand,
        "brand-foreground": bg if contrast_ratio(brand, bg) > contrast_ratio(brand, fg) else fg,
        "brand-muted": hsl_to_hex(bh, bs*0.2, min(bl+35, 95)),
        "accent": (theme_extras or {}).get("accents", [brand])[0] if theme_extras else brand,
        "accent-foreground": bg if contrast_ratio(brand, bg) > contrast_ratio(brand, fg) else fg,
        "destructive": (theme_extras or {}).get("semantic", {}).get("destructive", "#ef4444"),
        "destructive-foreground": "#ffffff",
        "warning": (theme_extras or {}).get("semantic", {}).get("warning", "#f59e0b"),
        "warning-foreground": "#0a0a0a",
        "success": (theme_extras or {}).get("semantic", {}).get("success", "#22c55e"),
        "success-foreground": "#ffffff",
        "info": (theme_extras or {}).get("semantic", {}).get("info", hsl_to_hex((bh+180)%360, bs*0.7, 48)),
        "info-foreground": "#ffffff",
        "control-bg": hsl_to_hex(bg_h, bg_s*0.3, max(bg_l-2, 0)),
        "control-border": hsl_to_hex(fg_h, fg_s*0.15, min(fg_l+75, 86)),
        "control-focus": brand,
    }

    # --- Dark mode ---
    dark = {
        "background": hsl_to_hex(bh, bs*0.08, 5),
        "background-subtle": hsl_to_hex(bh, bs*0.06, 8),
        "background-muted": hsl_to_hex(bh, bs*0.05, 12),
        "background-emphasis": hsl_to_hex(bh, bs*0.04, 16),
        "foreground": hsl_to_hex(0, 0, 96),
        "foreground-secondary": hsl_to_hex(0, 0, 72),
        "foreground-tertiary": hsl_to_hex(0, 0, 52),
        "foreground-muted": hsl_to_hex(0, 0, 36),
        "border": hsl_to_hex(bh, bs*0.05, 16),
        "border-subtle": hsl_to_hex(bh, bs*0.03, 12),
        "border-strong": hsl_to_hex(bh, bs*0.08, 24),
        "border-stronger": hsl_to_hex(bh, bs*0.1, 32),
        "brand": hsl_to_hex(bh, bs*0.85, min(bl+5, 65)),
        "brand-foreground": "#ffffff",
        "brand-muted": hsl_to_hex(bh, bs*0.25, 15),
        "accent": hsl_to_hex(bh, bs*0.85, min(bl+5, 65)),
        "accent-foreground": "#ffffff",
        "destructive": "#f87171",
        "destructive-foreground": "#ffffff",
        "warning": "#fbbf24",
        "warning-foreground": "#0a0a0a",
        "success": "#4ade80",
        "success-foreground": "#0a0a0a",
        "info": hsl_to_hex((bh+180)%360, bs*0.5, 55),
        "info-foreground": "#ffffff",
        "control-bg": hsl_to_hex(bh, bs*0.05, 7),
        "control-border": hsl_to_hex(bh, bs*0.08, 20),
        "control-focus": hsl_to_hex(bh, bs*0.85, min(bl+5, 65)),
    }

    types = type_scale(16, ratio_val, grid)
    spaces = spacing_scale(grid)

    radius_map = {"sm": (0.25,0.375,0.5,0.75), "md": (0.375,0.5,0.75,1.0), "lg": (0.5,0.75,1.0,1.5)}
    r = radius_map.get(radius, radius_map["md"])

    # --- Output CSS ---
    print("@tailwind base;")
    print("@tailwind components;")
    print("@tailwind utilities;")
    print()
    print("@layer base {")
    print("  :root {")

    # Colors
    print("    /* Background hierarchy */")
    for key in ["background","background-subtle","background-muted","background-emphasis"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()
    print("    /* Foreground hierarchy */")
    for key in ["foreground","foreground-secondary","foreground-tertiary","foreground-muted"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()
    print("    /* Border hierarchy */")
    for key in ["border","border-subtle","border-strong","border-stronger"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()
    print("    /* Brand & Accent */")
    for key in ["brand","brand-foreground","brand-muted","accent","accent-foreground"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()
    print("    /* Semantic */")
    for key in ["destructive","destructive-foreground","warning","warning-foreground","success","success-foreground","info","info-foreground"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()
    print("    /* Controls */")
    for key in ["control-bg","control-border","control-focus"]:
        print(f"    --{key}: {to_hsl_css(light[key])};")
    print()

    # Extra accents and chart colors from theme
    if theme_extras:
        accents = theme_extras.get("accents", [])
        if accents:
            print("    /* Accent Palette */")
            for i, c in enumerate(accents):
                print(f"    --accent-{i+1}: {to_hsl_css(c)};")
            print()

        charts = theme_extras.get("chart_colors", [])
        if charts:
            print("    /* Chart / Visualization Colors */")
            for i, c in enumerate(charts):
                print(f"    --chart-{i+1}: {to_hsl_css(c)};")
            print()

    # Brand shade scale (50-950)
    # Import shade scale function inline to avoid circular imports
    bh_brand, bs_brand, bl_brand = hex_to_hsl(brand)
    shade_targets = {
        50: 97, 100: 94, 200: 86, 300: 77, 400: 66,
        500: bl_brand, 600: max(bl_brand-10, 25), 700: max(bl_brand-22, 18),
        800: max(bl_brand-33, 12), 900: max(bl_brand-42, 8), 950: max(bl_brand-48, 4)
    }
    print("    /* Brand Shade Scale */")
    for step in sorted(shade_targets.keys()):
        target_l = shade_targets[step]
        adj_s = bs_brand * (0.3 + 0.7 * (step/500)) if step < 500 else (bs_brand if step == 500 else min(bs_brand*1.1, 100))
        shade = hsl_to_hex(bh_brand, adj_s, target_l)
        print(f"    --brand-{step}: {to_hsl_css(shade)};")
    print()

    # Typography
    print("    /* Typography Scale */")
    for name, vals in types.items():
        print(f"    --text-{name}: {vals['size']/16:.4f}rem; /* {vals['size']}px, lh: {vals['lh']}px */")
    print()

    # Spacing
    print(f"    /* Spacing Scale ({grid}px grid) */")
    for val in spaces:
        print(f"    --space-{val}: {val/16:.4f}rem; /* {val}px */")
    print()

    # Radius
    print("    /* Radius Scale */")
    print(f"    --radius-sm: {r[0]}rem;")
    print(f"    --radius: {r[1]}rem;")
    print(f"    --radius-lg: {r[2]}rem;")
    print(f"    --radius-xl: {r[3]}rem;")
    print()

    # Z-index scale
    print("    /* Z-Index Scale */")
    print("    --z-base: 0;")
    print("    --z-dropdown: 100;")
    print("    --z-sticky: 200;")
    print("    --z-overlay: 300;")
    print("    --z-modal: 400;")
    print("    --z-popover: 500;")
    print("    --z-toast: 600;")
    print()

    # Shadow scale (computed from depth strategy)
    depth = (theme_extras or {}).get("depth", "subtle-shadows")
    print("    /* Shadow Scale */")
    if depth == "borders-only" or depth == "surface-shifts":
        print("    --shadow-sm: none;")
        print("    --shadow: none;")
        print("    --shadow-md: none;")
        print("    --shadow-lg: none;")
    elif depth == "subtle-shadows":
        print("    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.03);")
        print("    --shadow: 0 1px 3px 0 rgb(0 0 0 / 0.05);")
        print("    --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.05);")
        print("    --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.05);")
    elif depth == "layered-shadows":
        print("    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);")
        print("    --shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);")
        print("    --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);")
        print("    --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);")
    else:
        print("    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);")
        print("    --shadow: 0 1px 3px 0 rgb(0 0 0 / 0.08);")
        print("    --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.08);")
        print("    --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.08);")
    print()

    # Motion tokens
    print("    /* Motion */")
    print("    --duration-fast: 100ms;")
    print("    --duration-normal: 200ms;")
    print("    --duration-slow: 300ms;")
    print("    --ease-out: cubic-bezier(0, 0, 0.2, 1);")
    print("    --ease-in: cubic-bezier(0.4, 0, 1, 0.8);")
    print("    --ease-in-out: cubic-bezier(0.4, 0, 0.2, 1);")
    print()

    # Content width tokens
    print("    /* Content Width */")
    print("    --measure-narrow: 45ch;")
    print("    --measure: 65ch;")
    print("    --measure-wide: 80ch;")
    print()

    # Interactive element sizing (harmonized heights)
    base_font = types["base"]["size"]
    print("    /* Interactive Element Sizes */")
    for size_name, (font_key, pad_mult) in [("sm", ("sm", 1.5)), ("md", ("base", 2)), ("lg", ("lg", 2.5))]:
        font_size = types.get(font_key, types["base"])["size"]
        padding = snap(font_size * pad_mult / 2, grid)
        height = font_size + 2 * padding + 2  # +2 for border
        height = snap(height, grid)  # Snap to grid
        print(f"    --control-height-{size_name}: {height/16:.4f}rem; /* {height}px: {font_size}px font + {padding}px padding + 2px border */")
    print()

    print("  }")
    print()

    # Dark mode
    print("  .dark {")
    for key in ["background","background-subtle","background-muted","background-emphasis",
                "foreground","foreground-secondary","foreground-tertiary","foreground-muted",
                "border","border-subtle","border-strong","border-stronger",
                "brand","brand-foreground","brand-muted","accent","accent-foreground",
                "destructive","destructive-foreground","warning","warning-foreground",
                "success","success-foreground","info","info-foreground",
                "control-bg","control-border","control-focus"]:
        print(f"    --{key}: {to_hsl_css(dark[key])};")
    print("  }")
    print("}")
    print()

    # Base styles
    print("@layer base {")
    print("  * { border-color: hsl(var(--border)); }")
    print("  body {")
    print("    background-color: hsl(var(--background));")
    print("    color: hsl(var(--foreground));")
    print("    font-size: var(--text-base);")
    print(f"    line-height: {types['base']['lh']/types['base']['size']:.3f};")
    print("  }")
    print("  ::selection {")
    print("    background-color: hsl(var(--brand) / 0.2);")
    print("    color: hsl(var(--foreground));")
    print("  }")
    print("  :focus-visible {")
    print("    outline: 2px solid hsl(var(--control-focus));")
    print("    outline-offset: 2px;")
    print("  }")
    print("  input, textarea, select {")
    print("    background-color: hsl(var(--control-bg));")
    print("    border-color: hsl(var(--control-border));")
    print("  }")
    print("}")

    # Contrast report
    print()
    cr_main = contrast_ratio(light["foreground"], light["background"])
    cr_brand = contrast_ratio(light["brand-foreground"], light["brand"])
    cr_secondary = contrast_ratio(light["foreground-secondary"], light["background"])
    type_sizes = ', '.join(f"{v['size']}px" for v in types.values())
    space_sizes = ', '.join(f"{v}px" for v in spaces)
    print(f"/* Contrast Report:")
    print(f"   foreground on background: {cr_main:.1f}:1 ({'PASS' if cr_main >= 4.5 else 'FAIL'})")
    print(f"   brand-foreground on brand: {cr_brand:.1f}:1 ({'PASS' if cr_brand >= 4.5 else 'FAIL'})")
    print(f"   secondary on background: {cr_secondary:.1f}:1 ({'PASS' if cr_secondary >= 4.5 else 'FAIL'})")
    print(f"   Type scale: {type_sizes}")
    print(f"   Spacing: {space_sizes}")
    print(f"*/")

def main():
    parser = argparse.ArgumentParser(description="Generate a complete design system as CSS")
    parser.add_argument("--brand", help="Brand color hex (e.g. '#3b82f6')")
    parser.add_argument("--bg", default=None, help="Background color hex")
    parser.add_argument("--fg", default=None, help="Foreground color hex")
    parser.add_argument("--ratio", default=None, help="Type scale ratio (number or name)")
    parser.add_argument("--grid", type=int, default=None, help="Baseline grid unit in px")
    parser.add_argument("--radius", default=None, choices=["sm","md","lg"])
    parser.add_argument("--theme", help="Use a theme seed (e.g. midnight, paper, forest)")
    parser.add_argument("--list-themes", action="store_true", help="List available theme seeds")
    parser.add_argument("--list-domains", action="store_true", help="List domain-to-theme recommendations")

    args = parser.parse_args()

    if args.list_themes:
        list_themes()
        sys.exit(0)

    if args.list_domains:
        seeds_path = os.path.join(SCRIPT_DIR, "..", "assets", "theme-seeds.json")
        with open(seeds_path) as f:
            data = json.load(f)
        domains = data.get("domains", {})
        print(f"Domain → Theme Recommendations ({len(domains)} domains):\n")
        for domain, themes in sorted(domains.items()):
            print(f"  {domain:22s}  {', '.join(themes)}")
        sys.exit(0)

    # Load theme seed if specified
    if args.theme:
        theme = load_theme(args.theme)
        brand = args.brand or theme["brand"]
        bg = args.bg or theme["bg"]
        fg = args.fg or theme["fg"]
        ratio_str = args.ratio or theme.get("ratio", "1.25")
        grid = args.grid or theme.get("grid", 4)
        radius = args.radius or theme.get("radius", "md")
        print(f"/* Theme: {args.theme} — {theme['description']} */", file=sys.stderr)
        if theme.get("fonts"):
            print(f"/* Recommended fonts: {theme['fonts']['heading']} (heading), {theme['fonts']['body']} (body) */", file=sys.stderr)
        theme_extras = theme  # Pass full theme for accents, charts, semantic overrides
    else:
        if not args.brand:
            parser.error("--brand is required (or use --theme)")
        brand = args.brand
        bg = args.bg or "#ffffff"
        fg = args.fg or "#0a0a0a"
        ratio_str = args.ratio or "1.25"
        grid = args.grid or 4
        radius = args.radius or "md"
        theme_extras = None

    ratio_val = NAMED_RATIOS.get(ratio_str) or float(ratio_str)
    generate(brand, bg, fg, ratio_val, grid, radius, theme_extras)

if __name__ == "__main__":
    main()
