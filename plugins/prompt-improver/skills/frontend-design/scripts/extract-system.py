#!/usr/bin/env python3
"""Extract design system from an existing project.

Scans code for colors, fonts, spacing, and patterns to generate
a .frontend-design/system.md draft.

Usage:
  python3 extract-system.py --dir .
  python3 extract-system.py --dir ./my-project --output system.md
"""
import re
import os
import sys
import argparse
import glob as globmod
from collections import Counter

def find_files(project_dir, extensions):
    """Find all matching files, excluding node_modules and build dirs."""
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    return [f for f in files if "node_modules" not in f and ".next" not in f and ".astro" not in f]

def extract_colors(project_dir):
    """Find all color values used in the project (Tailwind, CSS, styled-components)."""
    colors = Counter()
    tailwind_colors = Counter()
    token_colors = Counter()

    files = find_files(project_dir, ["*.tsx", "*.jsx", "*.css", "*.vue", "*.svelte", "*.module.css", "*.ts", "*.js"])

    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()

            # Hex colors
            for match in re.finditer(r'#([0-9a-fA-F]{6})\b', content):
                colors[f"#{match.group(1).lower()}"] += 1

            # Tailwind color classes
            for match in re.finditer(r'(?:bg|text|border|ring|fill|stroke)-([a-z]+-\d+)\b', content):
                tailwind_colors[match.group(1)] += 1

            # CSS custom properties (tokens)
            for match in re.finditer(r'var\(--([a-z-]+)\)', content):
                token_colors[match.group(1)] += 1

            # styled-components / CSS-in-JS theme colors
            for match in re.finditer(r'(?:color|background|backgroundColor|borderColor)\s*[:=]\s*["\']?(#[0-9a-fA-F]{6})', content):
                colors[match.group(1).lower()] += 1

            # CSS color/background properties in .css/.module.css files
            if filepath.endswith('.css'):
                for match in re.finditer(r'(?:color|background-color|border-color)\s*:\s*(#[0-9a-fA-F]{6})', content):
                    colors[match.group(1).lower()] += 1

            # RGB/HSL values in CSS
            for match in re.finditer(r'(?:rgb|hsl)a?\([^)]+\)', content):
                colors[match.group(0)] += 1
        except (IOError, UnicodeDecodeError):
            continue

    return colors, tailwind_colors, token_colors

def extract_fonts(project_dir):
    """Find all font-family declarations."""
    fonts = set()
    files = find_files(project_dir, ["*.tsx", "*.ts", "*.css", "*.jsx"])

    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()

            # next/font imports — match the imported font names (capitalized)
            for match in re.finditer(r'import\s*\{\s*([^}]+)\}\s*from\s*["\']next/font/google["\']', content):
                for font in re.findall(r'([A-Z][a-zA-Z_]+)', match.group(1)):
                    fonts.add(font.replace('_', ' '))

            # CSS font-family
            for match in re.finditer(r'font-family:\s*["\']?([^;"\'\n]+)', content):
                fonts.add(match.group(1).strip().strip("'\"").split(',')[0].strip())

            # @fontsource imports
            for match in re.finditer(r'@fontsource/([a-z-]+)', content):
                fonts.add(match.group(1).replace('-', ' ').title())
        except (IOError, UnicodeDecodeError):
            continue

    return fonts

def extract_spacing(project_dir):
    """Find spacing values used in Tailwind classes."""
    spacing = Counter()
    files = find_files(project_dir, ["*.tsx", "*.jsx", "*.vue", "*.svelte"])

    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()

            # Tailwind spacing classes (p-4, m-2, gap-6, etc.)
            for match in re.finditer(r'(?:p|m|px|py|pt|pb|pl|pr|mx|my|mt|mb|ml|mr|gap|gap-x|gap-y|space-x|space-y)-(\d+)\b', content):
                val = int(match.group(1))
                spacing[val * 4] += 1  # Convert Tailwind units to px

            # Arbitrary values
            for match in re.finditer(r'(?:p|m|gap)-\[(\d+)px\]', content):
                spacing[int(match.group(1))] += 1
        except (IOError, UnicodeDecodeError):
            continue

    return spacing

def extract_globals_tokens(project_dir):
    """Parse CSS files for existing design tokens (custom properties)."""
    tokens = {}
    # Check common locations, then fall back to any .css file with custom properties
    candidates = [
        "app/globals.css", "src/app/globals.css", "styles/globals.css",
        "src/styles/globals.css", "src/index.css", "styles/index.css",
        "src/styles/variables.css", "styles/variables.css",
    ]
    for candidate in candidates:
        path = os.path.join(project_dir, candidate)
        if os.path.exists(path):
            with open(path) as f:
                for match in re.finditer(r'--([a-z][\w-]*)\s*:\s*([^;]+)', f.read()):
                    tokens[match.group(1)] = match.group(2).strip()
            if tokens:
                break
    # If nothing found in standard locations, search all CSS files
    if not tokens:
        for css_file in find_files(project_dir, ["*.css"]):
            try:
                with open(css_file) as f:
                    for match in re.finditer(r'--([a-z][\w-]*)\s*:\s*([^;]+)', f.read()):
                        tokens[match.group(1)] = match.group(2).strip()
            except (IOError, UnicodeDecodeError):
                continue
    return tokens

def detect_depth_strategy(project_dir):
    """Detect depth strategy from code patterns."""
    shadow_count = 0
    border_count = 0

    files = find_files(project_dir, ["*.tsx", "*.jsx", "*.css"])
    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()
            shadow_count += len(re.findall(r'shadow-(?:sm|md|lg|xl)|box-shadow', content))
            border_count += len(re.findall(r'border(?:-[trbl])?(?:\s|["\'=])', content))
        except (IOError, UnicodeDecodeError):
            continue

    if shadow_count == 0:
        return "borders-only"
    elif shadow_count > border_count:
        return "layered-shadows"
    else:
        return "subtle-shadows"

def generate_system_md(project_dir):
    """Generate a system.md from extracted patterns."""
    colors, tw_colors, token_colors = extract_colors(project_dir)
    fonts = extract_fonts(project_dir)
    spacing = extract_spacing(project_dir)
    tokens = extract_globals_tokens(project_dir)
    depth = detect_depth_strategy(project_dir)

    # Determine grid unit from spacing values
    spacing_vals = sorted(spacing.keys())
    grid = 4
    if spacing_vals:
        diffs = [spacing_vals[i+1] - spacing_vals[i] for i in range(min(5, len(spacing_vals)-1))]
        if diffs:
            from math import gcd
            from functools import reduce
            grid = reduce(gcd, [d for d in diffs if d > 0]) if any(d > 0 for d in diffs) else 4
            if grid not in (4, 8):
                grid = 4

    output = []
    output.append("# Design System (Auto-Extracted)")
    output.append("")
    output.append("> Generated by extract-system.py. Review and customize.")
    output.append("")
    output.append("## Direction")
    output.append("<!-- Describe the design direction after reviewing extracted values -->")
    output.append("")
    output.append("## Intent")
    output.append("- **Who:** <!-- Fill in -->")
    output.append("- **Task:** <!-- Fill in -->")
    output.append("- **Feel:** <!-- Fill in -->")
    output.append("")

    # Colors
    output.append("## Color Palette")
    if tokens:
        output.append("")
        output.append("### From Design Tokens")
        output.append("| Token | Value |")
        output.append("|-------|-------|")
        for name, val in sorted(tokens.items()):
            if any(k in name for k in ["background", "foreground", "brand", "accent", "border"]):
                output.append(f"| --{name} | {val} |")

    if colors:
        output.append("")
        output.append("### Hex Colors Found in Code")
        for color, count in colors.most_common(10):
            output.append(f"- `{color}` (used {count}x)")

    if tw_colors:
        output.append("")
        output.append("### Tailwind Color Classes")
        for color, count in tw_colors.most_common(10):
            output.append(f"- `{color}` (used {count}x)")

    output.append("")

    # Typography
    output.append("## Typography")
    if fonts:
        for i, font in enumerate(sorted(fonts)):
            role = "Heading" if i == 0 else "Body" if i == 1 else f"Font {i+1}"
            output.append(f"- **{role}:** {font}")
    else:
        output.append("- No custom fonts detected (using system defaults)")
    output.append("")

    # Depth
    output.append(f"## Depth Strategy")
    output.append(f"Detected: **{depth}**")
    output.append("")

    # Spacing
    output.append(f"## Spacing")
    output.append(f"- **Grid unit:** {grid}px")
    if spacing_vals:
        output.append(f"- **Values used:** {', '.join(f'{v}px' for v in spacing_vals[:12])}")
        off_grid = [v for v in spacing_vals if v % grid != 0]
        if off_grid:
            output.append(f"- **Off-grid values:** {', '.join(f'{v}px' for v in off_grid)} ← should be adjusted")
    output.append("")

    output.append("## Signature Element")
    output.append("<!-- Identify after reviewing the extracted patterns -->")
    output.append("")
    output.append("## Key Patterns")
    output.append("<!-- Add component patterns used 2+ times -->")

    return "\n".join(output)

def main():
    parser = argparse.ArgumentParser(description="Extract design system from existing project")
    parser.add_argument("--dir", default=".", help="Project directory to scan")
    parser.add_argument("--output", help="Output file path (default: stdout)")

    args = parser.parse_args()

    if not os.path.isdir(args.dir):
        print(f"Directory not found: {args.dir}", file=sys.stderr)
        sys.exit(1)

    result = generate_system_md(args.dir)

    if args.output:
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, 'w') as f:
            f.write(result)
        print(f"Extracted design system to {args.output}", file=sys.stderr)
    else:
        print(result)

if __name__ == "__main__":
    main()
