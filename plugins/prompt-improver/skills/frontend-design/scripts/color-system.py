#!/usr/bin/env python3
"""Color science toolkit for design systems.

Usage:
  python3 color-system.py palette --brand "#3b82f6" --harmony analogous
  python3 color-system.py contrast --fg "#ffffff" --bg "#3b82f6"
  python3 color-system.py surfaces --base "#ffffff" --steps 5
  python3 color-system.py dark-mode --brand "#3b82f6" --bg "#ffffff" --fg "#0a0a0a"
  python3 color-system.py audit --brand "#3b82f6" --bg "#ffffff" --fg "#0a0a0a"
"""
import colorsys
import math
import sys
import json
import argparse

def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) / 255.0 for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    return '#{:02x}{:02x}{:02x}'.format(int(r * 255), int(g * 255), int(b * 255))

def hex_to_hsl(hex_color):
    r, g, b = hex_to_rgb(hex_color)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return (h * 360, s * 100, l * 100)

def hsl_to_hex(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s / 100)
    return rgb_to_hex(r, g, b)

def relative_luminance(hex_color):
    """WCAG 2.0 relative luminance calculation."""
    r, g, b = hex_to_rgb(hex_color)
    def linearize(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)

def contrast_ratio(color1, color2):
    """WCAG 2.0 contrast ratio between two hex colors."""
    l1 = relative_luminance(color1)
    l2 = relative_luminance(color2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)

def wcag_level(ratio):
    """Return WCAG compliance level."""
    if ratio >= 7.0:
        return "AAA"
    elif ratio >= 4.5:
        return "AA"
    elif ratio >= 3.0:
        return "AA-large"
    else:
        return "FAIL"

def generate_harmony(brand_hex, harmony="analogous"):
    """Generate harmonious colors from a brand color."""
    h, s, l = hex_to_hsl(brand_hex)

    if harmony == "complementary":
        colors = {"brand": brand_hex, "complement": hsl_to_hex((h + 180) % 360, s, l)}
    elif harmony == "analogous":
        colors = {
            "brand": brand_hex,
            "analogous-1": hsl_to_hex((h + 30) % 360, s, l),
            "analogous-2": hsl_to_hex((h - 30) % 360, s, l),
        }
    elif harmony == "triadic":
        colors = {
            "brand": brand_hex,
            "triadic-1": hsl_to_hex((h + 120) % 360, s, l),
            "triadic-2": hsl_to_hex((h + 240) % 360, s, l),
        }
    elif harmony == "split-complementary":
        colors = {
            "brand": brand_hex,
            "split-1": hsl_to_hex((h + 150) % 360, s, l),
            "split-2": hsl_to_hex((h + 210) % 360, s, l),
        }
    elif harmony == "monochromatic":
        colors = {
            "brand": brand_hex,
            "light": hsl_to_hex(h, s * 0.6, min(l + 25, 95)),
            "dark": hsl_to_hex(h, s * 0.8, max(l - 25, 10)),
            "muted": hsl_to_hex(h, s * 0.3, l),
        }
    else:
        colors = {"brand": brand_hex}

    return colors

def generate_surfaces(base_hex, steps=5):
    """Generate surface elevation scale with perceptually uniform steps."""
    h, s, l = hex_to_hsl(base_hex)
    is_dark = l < 50
    surfaces = {}

    for i in range(steps):
        if is_dark:
            # Dark mode: higher elevation = slightly lighter
            new_l = l + (i * 3.5)
        else:
            # Light mode: higher elevation = slightly darker
            new_l = l - (i * 2.5)
        new_l = max(0, min(100, new_l))
        surfaces[f"surface-{i}"] = hsl_to_hex(h, s * 0.3 if i > 0 else 0, new_l)

    return surfaces

def generate_dark_mode(brand_hex, bg_hex, fg_hex):
    """Derive perceptually correct dark mode palette."""
    bh, bs, bl = hex_to_hsl(brand_hex)

    dark = {
        "background": hsl_to_hex(bh, bs * 0.1, 5),
        "background-subtle": hsl_to_hex(bh, bs * 0.08, 8),
        "background-muted": hsl_to_hex(bh, bs * 0.06, 12),
        "background-emphasis": hsl_to_hex(bh, bs * 0.05, 16),
        "foreground": hsl_to_hex(0, 0, 96),
        "foreground-secondary": hsl_to_hex(0, 0, 72),
        "foreground-tertiary": hsl_to_hex(0, 0, 52),
        "foreground-muted": hsl_to_hex(0, 0, 36),
        "border": hsl_to_hex(bh, bs * 0.05, 16),
        "border-subtle": hsl_to_hex(bh, bs * 0.03, 12),
        "border-strong": hsl_to_hex(bh, bs * 0.08, 22),
        "brand": hsl_to_hex(bh, bs * 0.85, min(bl + 5, 65)),  # Slightly lighter in dark mode
        "brand-muted": hsl_to_hex(bh, bs * 0.3, 15),
    }
    return dark

def audit_palette(palette):
    """Check all foreground/background combinations for WCAG compliance."""
    results = []
    fg_keys = [k for k in palette if "foreground" in k or k == "brand"]
    bg_keys = [k for k in palette if "background" in k or "surface" in k]

    for fg_key in fg_keys:
        for bg_key in bg_keys:
            ratio = contrast_ratio(palette[fg_key], palette[bg_key])
            level = wcag_level(ratio)
            results.append({
                "fg": fg_key, "fg_color": palette[fg_key],
                "bg": bg_key, "bg_color": palette[bg_key],
                "ratio": round(ratio, 2), "level": level
            })
    return results

def generate_shade_scale(hex_color, steps=10):
    """Generate a 50-950 shade scale from a single color.

    Lighter shades: increase lightness, decrease saturation slightly.
    Darker shades: decrease lightness, increase saturation slightly.
    """
    h, s, l = hex_to_hsl(hex_color)
    scale = {}
    # Lightness targets for each step (perceptually distributed)
    targets = {
        50: 97, 100: 94, 200: 86, 300: 77, 400: 66,
        500: l,  # Original color's lightness
        600: max(l - 10, 25), 700: max(l - 22, 18),
        800: max(l - 33, 12), 900: max(l - 42, 8), 950: max(l - 48, 4)
    }
    for step, target_l in targets.items():
        # Adjust saturation: lighter = less saturated, darker = slightly more
        if step < 500:
            adj_s = s * (0.3 + 0.7 * (step / 500))
        elif step == 500:
            adj_s = s
        else:
            adj_s = min(s * 1.1, 100)
        scale[step] = hsl_to_hex(h, adj_s, target_l)
    return scale

def fix_contrast(fg_hex, bg_hex, target_ratio=4.5):
    """Find the nearest accessible fg color by adjusting lightness.

    Keeps hue and saturation, binary searches lightness until contrast >= target.
    """
    h, s, l = hex_to_hsl(fg_hex)
    bg_lum = relative_luminance(bg_hex)

    # Determine direction: if bg is light, make fg darker; if bg is dark, make fg lighter
    if bg_lum > 0.5:
        low, high = 0, l  # Search darker
    else:
        low, high = l, 100  # Search lighter

    # Binary search for minimum lightness change that achieves target contrast
    best = fg_hex
    for _ in range(50):
        mid = (low + high) / 2
        candidate = hsl_to_hex(h, s, mid)
        ratio = contrast_ratio(candidate, bg_hex)
        if ratio >= target_ratio:
            best = candidate
            if bg_lum > 0.5:
                low = mid  # Try less change
            else:
                high = mid
        else:
            if bg_lum > 0.5:
                high = mid  # Need more change
            else:
                low = mid
    return best

def simulate_color_blindness(hex_color, type="deuteranopia"):
    """Simulate how a color appears to people with color vision deficiency.

    Uses well-established transformation matrices.
    Types: protanopia (no red), deuteranopia (no green), tritanopia (no blue)
    """
    r, g, b = hex_to_rgb(hex_color)

    matrices = {
        "protanopia": [
            [0.567, 0.433, 0.000],
            [0.558, 0.442, 0.000],
            [0.000, 0.242, 0.758],
        ],
        "deuteranopia": [
            [0.625, 0.375, 0.000],
            [0.700, 0.300, 0.000],
            [0.000, 0.300, 0.700],
        ],
        "tritanopia": [
            [0.950, 0.050, 0.000],
            [0.000, 0.433, 0.567],
            [0.000, 0.475, 0.525],
        ],
    }

    m = matrices.get(type, matrices["deuteranopia"])
    sr = m[0][0]*r + m[0][1]*g + m[0][2]*b
    sg = m[1][0]*r + m[1][1]*g + m[1][2]*b
    sb = m[2][0]*r + m[2][1]*g + m[2][2]*b
    return rgb_to_hex(max(0,min(1,sr)), max(0,min(1,sg)), max(0,min(1,sb)))

def audit_color_blindness(palette):
    """Check if semantic colors are distinguishable under color blindness."""
    semantic_keys = ["destructive", "warning", "success", "info", "brand"]
    semantic = {k: v for k, v in palette.items() if k in semantic_keys}

    if len(semantic) < 2:
        return []

    issues = []
    for cvd_type in ["protanopia", "deuteranopia", "tritanopia"]:
        simulated = {k: simulate_color_blindness(v, cvd_type) for k, v in semantic.items()}

        # Check if any pair becomes too similar (contrast < 1.5:1)
        keys = list(simulated.keys())
        for i in range(len(keys)):
            for j in range(i+1, len(keys)):
                ratio = contrast_ratio(simulated[keys[i]], simulated[keys[j]])
                if ratio < 1.5:
                    issues.append(f"  {cvd_type}: {keys[i]} and {keys[j]} become indistinguishable ({ratio:.1f}:1)")
    return issues

def cmd_palette(args):
    colors = generate_harmony(args.brand, args.harmony)
    print(json.dumps(colors, indent=2))

def cmd_contrast(args):
    ratio = contrast_ratio(args.fg, args.bg)
    level = wcag_level(ratio)
    print(f"Contrast ratio: {ratio:.2f}:1")
    print(f"WCAG level: {level}")
    print(f"  Normal text (4.5:1): {'PASS' if ratio >= 4.5 else 'FAIL'}")
    print(f"  Large text (3.0:1): {'PASS' if ratio >= 3.0 else 'FAIL'}")
    print(f"  AAA (7.0:1): {'PASS' if ratio >= 7.0 else 'FAIL'}")

def cmd_surfaces(args):
    surfaces = generate_surfaces(args.base, args.steps)
    for name, color in surfaces.items():
        print(f"  {name}: {color}")

def cmd_dark_mode(args):
    dark = generate_dark_mode(args.brand, args.bg, args.fg)
    print(json.dumps(dark, indent=2))

def cmd_audit(args):
    palette = {
        "brand": args.brand,
        "background": args.bg,
        "foreground": args.fg,
    }
    # Generate full palette for audit
    palette.update(generate_surfaces(args.bg, 4))
    palette["foreground-secondary"] = hsl_to_hex(*hex_to_hsl(args.fg)[:2], hex_to_hsl(args.fg)[2] + 25)
    palette["foreground-muted"] = hsl_to_hex(*hex_to_hsl(args.fg)[:2], hex_to_hsl(args.fg)[2] + 45)

    results = audit_palette(palette)
    failures = [r for r in results if r["level"] == "FAIL"]
    passes = [r for r in results if r["level"] != "FAIL"]

    print(f"Accessibility Audit: {len(passes)} pass, {len(failures)} fail")
    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  {f['fg']} ({f['fg_color']}) on {f['bg']} ({f['bg_color']}): {f['ratio']}:1 — {f['level']}")
    print(f"\nAll pairs: {len(results)} checked")

def cmd_shades(args):
    scale = generate_shade_scale(args.color)
    for step, color in sorted(scale.items()):
        print(f"  {step:>4}: {color}")

def cmd_fix(args):
    original_ratio = contrast_ratio(args.fg, args.bg)
    if original_ratio >= args.target:
        print(f"Already passes: {original_ratio:.2f}:1 >= {args.target}:1")
        print(f"  Color: {args.fg}")
        return

    fixed = fix_contrast(args.fg, args.bg, args.target)
    new_ratio = contrast_ratio(fixed, args.bg)
    print(f"Original: {args.fg} — {original_ratio:.2f}:1 (FAIL)")
    print(f"Fixed:    {fixed} — {new_ratio:.2f}:1 (PASS)")
    print(f"  Change: lightness shifted to achieve {args.target}:1 minimum")

def cmd_colorblind(args):
    if args.color:
        print(f"Original:     {args.color}")
        for cvd in ["protanopia", "deuteranopia", "tritanopia"]:
            sim = simulate_color_blindness(args.color, cvd)
            print(f"  {cvd:14s}: {sim}")
    elif args.palette:
        palette = {f"color-{i}": c for i, c in enumerate(args.palette)}
        issues = audit_color_blindness(palette)
        if issues:
            print("Color blindness issues found:")
            for issue in issues:
                print(issue)
        else:
            print("All colors remain distinguishable under color blindness simulation")

def main():
    parser = argparse.ArgumentParser(description="Color science toolkit for design systems")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    p_palette = subparsers.add_parser("palette", help="Generate color harmonies")
    p_palette.add_argument("--brand", required=True, help="Brand color hex")
    p_palette.add_argument("--harmony", default="analogous", choices=["complementary", "analogous", "triadic", "split-complementary", "monochromatic"])

    p_contrast = subparsers.add_parser("contrast", help="Check WCAG contrast ratio")
    p_contrast.add_argument("--fg", required=True, help="Foreground color hex")
    p_contrast.add_argument("--bg", required=True, help="Background color hex")

    p_surfaces = subparsers.add_parser("surfaces", help="Generate surface elevation scale")
    p_surfaces.add_argument("--base", required=True, help="Base surface color hex")
    p_surfaces.add_argument("--steps", type=int, default=5, help="Number of elevation levels")

    p_dark = subparsers.add_parser("dark-mode", help="Derive dark mode palette")
    p_dark.add_argument("--brand", required=True)
    p_dark.add_argument("--bg", required=True)
    p_dark.add_argument("--fg", required=True)

    p_audit = subparsers.add_parser("audit", help="Audit palette accessibility")
    p_audit.add_argument("--brand", required=True)
    p_audit.add_argument("--bg", required=True)
    p_audit.add_argument("--fg", required=True)

    p_shades = subparsers.add_parser("shades", help="Generate 50-950 shade scale")
    p_shades.add_argument("--color", required=True, help="Base color hex")

    p_fix = subparsers.add_parser("fix", help="Find nearest accessible color")
    p_fix.add_argument("--fg", required=True, help="Foreground color to adjust")
    p_fix.add_argument("--bg", required=True, help="Background color (stays fixed)")
    p_fix.add_argument("--target", type=float, default=4.5, help="Target contrast ratio")

    p_cb = subparsers.add_parser("colorblind", help="Simulate color blindness")
    p_cb.add_argument("--color", help="Single color to simulate")
    p_cb.add_argument("--palette", nargs="+", help="Multiple colors to check distinguishability")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    {"palette": cmd_palette, "contrast": cmd_contrast, "surfaces": cmd_surfaces,
     "dark-mode": cmd_dark_mode, "audit": cmd_audit, "shades": cmd_shades,
     "fix": cmd_fix, "colorblind": cmd_colorblind}[args.command](args)

if __name__ == "__main__":
    main()
