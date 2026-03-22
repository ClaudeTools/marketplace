#!/usr/bin/env python3
"""Design audit — checks contrast, spacing, type scale compliance.

Usage:
  python3 audit-design.py --dir . --grid 4
  python3 audit-design.py --globals app/globals.css
"""
import re
import os
import sys
import argparse
import colorsys
import math
import glob as globmod

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16)/255.0 for i in (0,2,4))

def relative_luminance(hex_color):
    r,g,b = hex_to_rgb(hex_color)
    def lin(c): return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)

def contrast_ratio(c1,c2):
    l1,l2=relative_luminance(c1),relative_luminance(c2)
    return (max(l1,l2)+0.05)/(min(l1,l2)+0.05)

def audit_globals(filepath):
    """Parse globals.css and audit all token pairs for contrast."""
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath) as f:
        content = f.read()

    # Extract HSL tokens (shadcn format: "H S% L%")
    tokens = {}
    for match in re.finditer(r'--([a-z-]+):\s*(\d+\.?\d*)\s+(\d+\.?\d*)%\s+(\d+\.?\d*)%', content):
        name, h, s, l = match.group(1), float(match.group(2)), float(match.group(3)), float(match.group(4))
        r, g, b = colorsys.hls_to_rgb(h/360, l/100, s/100)
        tokens[name] = '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

    if not tokens:
        print("No HSL tokens found in globals.css")
        return

    print(f"Found {len(tokens)} tokens")
    print()

    # Check foreground/background combinations
    fg_tokens = {k:v for k,v in tokens.items() if "foreground" in k}
    bg_tokens = {k:v for k,v in tokens.items() if "background" in k}

    if fg_tokens and bg_tokens:
        print("Contrast Matrix:")
        failures = 0
        for fg_name, fg_color in fg_tokens.items():
            for bg_name, bg_color in bg_tokens.items():
                ratio = contrast_ratio(fg_color, bg_color)
                level = "AAA" if ratio >= 7 else "AA" if ratio >= 4.5 else "AA-lg" if ratio >= 3 else "FAIL"
                if level == "FAIL":
                    print(f"  FAIL: {fg_name} on {bg_name}: {ratio:.1f}:1")
                    failures += 1
        if failures == 0:
            print("  All pairs pass WCAG AA!")
        else:
            print(f"  {failures} pair(s) fail WCAG AA")

    # Check brand contrast
    if "brand" in tokens and "brand-foreground" in tokens:
        ratio = contrast_ratio(tokens["brand"], tokens["brand-foreground"])
        level = "PASS" if ratio >= 4.5 else "FAIL"
        print(f"\nBrand contrast: {ratio:.1f}:1 ({level})")

def audit_spacing(project_dir, grid):
    """Check Tailwind spacing classes for grid compliance."""
    violations = []

    extensions = ["*.tsx", "*.jsx", "*.vue", "*.svelte", "*.astro"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))

    files = [f for f in files if "node_modules" not in f and ".next" not in f]

    # Extract spacing values from Tailwind classes
    spacing_pattern = re.compile(r'(?:p|m|gap|space|w|h|top|left|right|bottom|inset)-\[(\d+)px\]')

    for filepath in files:
        with open(filepath) as f:
            for i, line in enumerate(f, 1):
                for match in spacing_pattern.finditer(line):
                    val = int(match.group(1))
                    if val % grid != 0:
                        violations.append(f"  {os.path.basename(filepath)}:{i}: {val}px is not on {grid}px grid")

    print(f"\nSpacing Grid Audit ({grid}px):")
    if violations:
        print(f"  {len(violations)} violation(s):")
        for v in violations[:10]:
            print(v)
        if len(violations) > 10:
            print(f"  ... and {len(violations)-10} more")
    else:
        print("  All spacing values on grid!")

def audit_vertical_rhythm(project_dir, grid):
    """Check if vertical spacings and line-heights are on the baseline grid."""
    violations = []
    extensions = ["*.tsx", "*.jsx", "*.vue", "*.svelte", "*.astro", "*.css"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if "node_modules" not in f and ".next" not in f]

    # Check for off-grid line-height values in CSS/Tailwind
    lh_pattern = re.compile(r'line-height:\s*(\d+)px')
    leading_pattern = re.compile(r'leading-\[(\d+)px\]')

    for filepath in files:
        try:
            with open(filepath) as f:
                for i, line in enumerate(f, 1):
                    for match in lh_pattern.finditer(line):
                        val = int(match.group(1))
                        if val % grid != 0:
                            violations.append(f"  {os.path.basename(filepath)}:{i}: line-height {val}px not on {grid}px grid")
                    for match in leading_pattern.finditer(line):
                        val = int(match.group(1))
                        if val % grid != 0:
                            violations.append(f"  {os.path.basename(filepath)}:{i}: leading-[{val}px] not on {grid}px grid")
        except (IOError, UnicodeDecodeError):
            continue

    print(f"\nVertical Rhythm Audit ({grid}px baseline):")
    if violations:
        print(f"  {len(violations)} violation(s):")
        for v in violations[:10]:
            print(v)
        if len(violations) > 10:
            print(f"  ... and {len(violations)-10} more")
    else:
        print("  All vertical spacings on baseline grid!")

def compute_completeness_score(project_dir, globals_path=None):
    """Compute a 0-100 design system completeness score."""
    score = 0
    max_score = 0
    details = []

    # 1. Token coverage (0-25 points)
    max_score += 25
    if globals_path and os.path.exists(globals_path):
        with open(globals_path) as f:
            content = f.read()
        token_count = len(re.findall(r'--[a-z]', content))
        if token_count >= 40:
            score += 25
            details.append(f"  Tokens: {token_count} ({25}/25)")
        elif token_count >= 20:
            pts = 15
            score += pts
            details.append(f"  Tokens: {token_count} ({pts}/25) — add more semantic tokens")
        elif token_count > 0:
            pts = 8
            score += pts
            details.append(f"  Tokens: {token_count} ({pts}/25) — minimal token coverage")
        else:
            details.append(f"  Tokens: 0 (0/25) — no design tokens found")
    else:
        details.append(f"  Tokens: no globals.css (0/25)")

    # 2. Raw value avoidance (0-20 points)
    max_score += 20
    raw_count = 0
    for ext in ["*.tsx", "*.jsx"]:
        for f in globmod.glob(os.path.join(project_dir, "**", ext), recursive=True):
            if "node_modules" in f: continue
            try:
                with open(f) as fh:
                    raw_count += len(re.findall(r'(?:text-white|bg-white|bg-black|text-black|bg-gray-|text-gray-)', fh.read()))
            except: pass
    if raw_count == 0:
        score += 20
        details.append(f"  Raw values: 0 ({20}/20)")
    elif raw_count < 5:
        pts = 12
        score += pts
        details.append(f"  Raw values: {raw_count} ({pts}/20)")
    else:
        details.append(f"  Raw values: {raw_count} (0/20)")

    # 3. Accessibility (0-20 points)
    max_score += 20
    # Check for alt text coverage
    img_total = 0
    img_with_alt = 0
    for ext in ["*.tsx", "*.jsx"]:
        for f in globmod.glob(os.path.join(project_dir, "**", ext), recursive=True):
            if "node_modules" in f: continue
            try:
                with open(f) as fh:
                    content = fh.read()
                    img_total += len(re.findall(r'<img\b', content))
                    img_with_alt += len(re.findall(r'<img[^>]+alt=', content))
            except: pass
    if img_total == 0 or img_with_alt == img_total:
        score += 20
        details.append(f"  Accessibility: all images have alt ({20}/20)")
    elif img_with_alt > img_total * 0.8:
        pts = 14
        score += pts
        details.append(f"  Accessibility: {img_with_alt}/{img_total} images have alt ({pts}/20)")
    else:
        pts = 5
        score += pts
        details.append(f"  Accessibility: {img_with_alt}/{img_total} images have alt ({pts}/20)")

    # 4. Component structure (0-15 points)
    max_score += 15
    large_files = 0
    total_components = 0
    for ext in ["*.tsx", "*.jsx"]:
        for f in globmod.glob(os.path.join(project_dir, "**", ext), recursive=True):
            if "node_modules" in f or ".next" in f: continue
            total_components += 1
            try:
                lines = sum(1 for _ in open(f))
                if lines > 200: large_files += 1
            except: pass
    if total_components > 0 and large_files == 0:
        score += 15
        details.append(f"  Components: {total_components} files, none >200 lines ({15}/15)")
    elif large_files <= 2:
        pts = 10
        score += pts
        details.append(f"  Components: {large_files} large files ({pts}/15)")
    else:
        details.append(f"  Components: {large_files} large files (0/15)")

    # 5. Anti-patterns (0-20 points)
    max_score += 20
    antipatterns = 0
    for ext in ["*.tsx", "*.jsx", "*.ts", "*.js"]:
        for f in globmod.glob(os.path.join(project_dir, "**", ext), recursive=True):
            if "node_modules" in f: continue
            try:
                with open(f) as fh:
                    content = fh.read()
                    antipatterns += len(re.findall(r'localStorage', content))
                    antipatterns += len(re.findall(r'useEffect\s*\([^)]*\{[^}]*fetch\(', content))
                    antipatterns += len(re.findall(r'space-[xy]-', content))
            except: pass
    if antipatterns == 0:
        score += 20
        details.append(f"  Anti-patterns: none found ({20}/20)")
    elif antipatterns < 3:
        pts = 12
        score += pts
        details.append(f"  Anti-patterns: {antipatterns} found ({pts}/20)")
    else:
        details.append(f"  Anti-patterns: {antipatterns} found (0/20)")

    print(f"\nDesign System Completeness: {score}/{max_score}")
    for d in details:
        print(d)

    return score

def main():
    parser = argparse.ArgumentParser(description="Audit design system quality")
    parser.add_argument("--dir", default=".", help="Project directory")
    parser.add_argument("--globals", help="Path to globals.css (auto-detected if not specified)")
    parser.add_argument("--grid", type=int, default=4, help="Baseline grid unit")

    args = parser.parse_args()

    globals_path = args.globals
    if not globals_path:
        for candidate in ["app/globals.css", "src/app/globals.css", "styles/globals.css"]:
            full = os.path.join(args.dir, candidate)
            if os.path.exists(full):
                globals_path = full
                break

    print("Design System Audit")
    print("=" * 40)

    if globals_path:
        audit_globals(globals_path)
    else:
        print("No globals.css found — skipping token audit")

    audit_spacing(args.dir, args.grid)

    audit_vertical_rhythm(args.dir, args.grid)
    compute_completeness_score(args.dir, globals_path)

if __name__ == "__main__":
    main()
