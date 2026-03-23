#!/usr/bin/env python3
"""Typography calculator — modular scales, fluid type, line height.

Usage:
  python3 type-scale.py scale --base 16 --ratio 1.25
  python3 type-scale.py scale --base 16 --ratio golden
  python3 type-scale.py fluid --min 16 --max 24 --min-vw 320 --max-vw 1280
  python3 type-scale.py css --base 16 --ratio 1.25 --grid 4
"""
import math
import sys
import json
import argparse

NAMED_RATIOS = {
    "minor-second": 1.067,
    "major-second": 1.125,
    "minor-third": 1.200,
    "major-third": 1.250,
    "perfect-fourth": 1.333,
    "augmented-fourth": 1.414,
    "perfect-fifth": 1.500,
    "golden": 1.618,
}

SCALE_NAMES = ["xs", "sm", "base", "lg", "xl", "2xl", "3xl", "4xl", "5xl"]

def modular_scale(base=16, ratio=1.25, steps_down=2, steps_up=6):
    """Generate a modular type scale."""
    sizes = []
    for i in range(-steps_down, steps_up + 1):
        size = base * (ratio ** i)
        sizes.append(round(size, 2))
    return sizes

def snap_to_grid(value, grid=4):
    """Snap a value to the nearest grid multiple."""
    return round(value / grid) * grid

def optimal_line_height(font_size, grid=4):
    """Calculate optimal line height snapped to baseline grid.

    Smaller text needs more relative line height.
    Larger text needs less.
    """
    # Base ratio that decreases with size
    ratio = 1.5 - (font_size - 12) * 0.008
    ratio = max(1.15, min(1.7, ratio))  # Clamp between 1.15 and 1.7
    raw = font_size * ratio
    return snap_to_grid(raw, grid)

def fluid_clamp(min_size, max_size, min_vw=320, max_vw=1280):
    """Generate CSS clamp() for fluid typography.

    Returns: clamp(min, preferred, max)
    where preferred = base + slope * 1vw
    """
    slope = (max_size - min_size) / (max_vw - min_vw)
    intercept = min_size - slope * min_vw

    # Convert to rem (assuming 16px base)
    min_rem = min_size / 16
    max_rem = max_size / 16
    intercept_rem = intercept / 16
    slope_vw = slope * 100  # Convert to vw units

    preferred = f"{intercept_rem:.4f}rem + {slope_vw:.4f}vw"
    return f"clamp({min_rem:.3f}rem, {preferred}, {max_rem:.3f}rem)"

def generate_spacing_scale(base=4, count=12):
    """Generate spacing scale from base unit."""
    # Common multipliers for 4-point grid
    if base == 4:
        multipliers = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24]
    elif base == 8:
        multipliers = [0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16]
    else:
        multipliers = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]

    return [int(base * m) for m in multipliers[:count]]

def cmd_scale(args):
    ratio = NAMED_RATIOS.get(args.ratio, None)
    if ratio is None:
        try:
            ratio = float(args.ratio)
        except ValueError:
            print(f"Unknown ratio: {args.ratio}")
            print(f"Named ratios: {', '.join(NAMED_RATIOS.keys())}")
            sys.exit(1)

    sizes = modular_scale(args.base, ratio)
    grid = args.grid

    print(f"Modular Scale: base={args.base}px, ratio={ratio}")
    print(f"Baseline grid: {grid}px")
    print()

    for i, size in enumerate(sizes):
        name = SCALE_NAMES[i] if i < len(SCALE_NAMES) else f"step-{i}"
        snapped = snap_to_grid(size, grid)
        lh = optimal_line_height(snapped, grid)
        print(f"  --text-{name}: {snapped}px  (line-height: {lh}px / {lh/snapped:.3f})")

def cmd_fluid(args):
    result = fluid_clamp(args.min, args.max, args.min_vw, args.max_vw)
    print(f"Fluid type: {args.min}px -> {args.max}px")
    print(f"Viewport: {args.min_vw}px -> {args.max_vw}px")
    print(f"\nCSS: font-size: {result};")

def cmd_css(args):
    ratio = NAMED_RATIOS.get(args.ratio, None) or float(args.ratio)
    sizes = modular_scale(args.base, ratio)
    grid = args.grid
    spacing = generate_spacing_scale(grid)

    print("/* Typography Scale */")
    for i, size in enumerate(sizes):
        name = SCALE_NAMES[i] if i < len(SCALE_NAMES) else f"step-{i}"
        snapped = snap_to_grid(size, grid)
        lh = optimal_line_height(snapped, grid)
        print(f"--text-{name}: {snapped / 16:.4f}rem; /* {snapped}px, line-height: {lh}px */")

    print()
    print("/* Spacing Scale */")
    spacing_names = ["px", "0.5", "1", "1.5", "2", "2.5", "3", "4", "5", "6", "8", "10", "12", "16", "20", "24"]
    for i, val in enumerate(spacing):
        name = spacing_names[i] if i < len(spacing_names) else str(i)
        print(f"--space-{name}: {val / 16:.4f}rem; /* {val}px */")

def main():
    parser = argparse.ArgumentParser(description="Typography calculator")
    subparsers = parser.add_subparsers(dest="command")

    p_scale = subparsers.add_parser("scale", help="Generate modular type scale")
    p_scale.add_argument("--base", type=float, default=16, help="Base font size in px")
    p_scale.add_argument("--ratio", default="1.25", help="Scale ratio (number or name: golden, major-third, etc)")
    p_scale.add_argument("--grid", type=int, default=4, help="Baseline grid unit in px")

    p_fluid = subparsers.add_parser("fluid", help="Generate fluid typography clamp()")
    p_fluid.add_argument("--min", type=float, required=True, help="Minimum font size px")
    p_fluid.add_argument("--max", type=float, required=True, help="Maximum font size px")
    p_fluid.add_argument("--min-vw", type=float, default=320, help="Minimum viewport width")
    p_fluid.add_argument("--max-vw", type=float, default=1280, help="Maximum viewport width")

    p_css = subparsers.add_parser("css", help="Output CSS custom properties")
    p_css.add_argument("--base", type=float, default=16)
    p_css.add_argument("--ratio", default="1.25")
    p_css.add_argument("--grid", type=int, default=4)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    {"scale": cmd_scale, "fluid": cmd_fluid, "css": cmd_css}[args.command](args)

if __name__ == "__main__":
    main()
