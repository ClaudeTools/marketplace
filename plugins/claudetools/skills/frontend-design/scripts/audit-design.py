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
import json
from datetime import datetime
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

    # Check foreground/background combinations using semantic pairing
    # X-foreground pairs with X (e.g., primary-foreground on primary)
    # foreground (bare) pairs with background (bare)
    fg_tokens = {k:v for k,v in tokens.items() if "foreground" in k}

    if fg_tokens:
        print("Contrast Matrix (semantic pairs):")
        failures = 0
        tested = 0
        unmatched = []
        for fg_name, fg_color in fg_tokens.items():
            # Determine the matching background token
            if fg_name == "foreground":
                bg_name = "background"
            else:
                # e.g., "primary-foreground" → "primary", "card-foreground" → "card"
                bg_name = fg_name.replace("-foreground", "")

            if bg_name in tokens:
                bg_color = tokens[bg_name]
                ratio = contrast_ratio(fg_color, bg_color)
                level = "AAA" if ratio >= 7 else "AA" if ratio >= 4.5 else "AA-lg" if ratio >= 3 else "FAIL"
                print(f"  {fg_name} on {bg_name}: {ratio:.1f}:1 ({level})")
                tested += 1
                if level == "FAIL":
                    failures += 1
            else:
                unmatched.append(fg_name)

        if failures == 0:
            print(f"  All {tested} pairs pass WCAG AA!")
        else:
            print(f"  {failures}/{tested} pair(s) fail WCAG AA")

        for u in unmatched:
            print(f"  INFO: {u} has no matching background token '{u.replace('-foreground', '')}'")
    else:
        print("No foreground tokens found — skipping contrast check")

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

    files = [f for f in files if not _is_build_path(f)]

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
    files = [f for f in files if not _is_build_path(f)]

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

BUILD_DIRS = {"node_modules", ".next", "dist", "build", "out", ".svelte-kit", ".output", ".nuxt", ".vercel", ".turbo", ".cache", ".parcel-cache", "storybook-static"}

def _is_build_path(filepath):
    """Check if a filepath passes through a build/vendor directory."""
    return any(d in filepath.split(os.sep) for d in BUILD_DIRS)

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
            if _is_build_path(f): continue
            try:
                with open(f) as fh:
                    raw_count += len(re.findall(r'(?:text-white|bg-white|bg-black|text-black|bg-gray-|text-gray-)', fh.read()))
            except (IOError, UnicodeDecodeError): pass
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
            if _is_build_path(f): continue
            try:
                with open(f) as fh:
                    content = fh.read()
                    img_total += len(re.findall(r'<img\b', content))
                    img_with_alt += len(re.findall(r'<img[^>]+alt=', content))
            except (IOError, UnicodeDecodeError): pass
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
            if _is_build_path(f): continue
            total_components += 1
            try:
                lines = sum(1 for _ in open(f))
                if lines > 200: large_files += 1
            except (IOError, UnicodeDecodeError): pass
    if total_components > 0 and large_files == 0:
        score += 15
        details.append(f"  Components: {total_components} files, none >200 lines ({15}/15)")
    elif large_files <= 2:
        pts = 10
        score += pts
        details.append(f"  Components: {large_files} large files ({pts}/15)")
    else:
        details.append(f"  Components: {large_files} large files (0/15)")

    # 5. Anti-patterns (0-20 points) — with category breakdown
    max_score += 20
    ap_categories = {"space-*": 0, "hardcoded colors": 0, "localStorage": 0, "inline styles": 0, "!important": 0, "fetch-in-useEffect": 0}
    for ext in ["*.tsx", "*.jsx", "*.ts", "*.js"]:
        for f in globmod.glob(os.path.join(project_dir, "**", ext), recursive=True):
            if _is_build_path(f): continue
            try:
                with open(f) as fh:
                    content = fh.read()
                    ap_categories["localStorage"] += len(re.findall(r'localStorage', content))
                    ap_categories["fetch-in-useEffect"] += len(re.findall(r'useEffect\s*\([^)]*\{[^}]*fetch\(', content))
                    ap_categories["space-*"] += len(re.findall(r'space-[xy]-', content))
                    ap_categories["hardcoded colors"] += len(re.findall(r'(?:text-white|bg-white|bg-black|text-black|bg-gray-|text-gray-|bg-red-|text-red-|bg-blue-|text-blue-|bg-green-|text-green-|bg-yellow-|text-yellow-)', content))
                    ap_categories["inline styles"] += len(re.findall(r'style=\{', content))
                    ap_categories["!important"] += len(re.findall(r'!important', content))
            except (IOError, UnicodeDecodeError): pass
    antipatterns = sum(ap_categories.values())
    breakdown = ", ".join(f"{v} {k}" for k, v in ap_categories.items() if v > 0)
    if antipatterns == 0:
        score += 20
        details.append(f"  Anti-patterns: none found ({20}/20)")
    elif antipatterns < 3:
        pts = 12
        score += pts
        details.append(f"  Anti-patterns: {antipatterns} total ({breakdown}) ({pts}/20)")
    else:
        details.append(f"  Anti-patterns: {antipatterns} total ({breakdown}) (0/20)")

    print(f"\nDesign System Completeness: {score}/{max_score}")
    for d in details:
        print(d)

    return score

def save_audit_history(project_dir, score, details_dict):
    """Save audit results to .frontend-design/audit-history.json and show deltas."""
    history_dir = os.path.join(project_dir, ".frontend-design")
    history_file = os.path.join(history_dir, "audit-history.json")

    entry = {
        "timestamp": datetime.now().isoformat(),
        "score": score,
        "breakdown": details_dict
    }

    history = []
    if os.path.exists(history_file):
        try:
            with open(history_file) as f:
                history = json.load(f)
        except (IOError, json.JSONDecodeError):
            history = []

    previous = history[-1] if history else None
    history.append(entry)

    os.makedirs(history_dir, exist_ok=True)
    with open(history_file, 'w') as f:
        json.dump(history, f, indent=2)

    if previous:
        delta = score - previous["score"]
        sign = "+" if delta >= 0 else ""
        prev_date = previous["timestamp"][:10]
        print(f"\nAudit History: Score {score}/100 ({sign}{delta} from last audit on {prev_date})")
    else:
        print(f"\nAudit History: Score {score}/100 (first audit)")

def audit_responsive(project_dir):
    """Check responsive/mobile best practices."""
    print("\nResponsive/Mobile Audit:")

    extensions = ["*.tsx", "*.jsx", "*.vue", "*.svelte", "*.astro"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if not _is_build_path(f)]

    small_fonts = 0
    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()
                small_fonts += len(re.findall(r'text-xs\b', content))
        except (IOError, UnicodeDecodeError):
            continue

    # Check for viewport meta in HTML files
    html_files = globmod.glob(os.path.join(project_dir, "**", "*.html"), recursive=True)
    html_files += globmod.glob(os.path.join(project_dir, "**/layout.tsx"), recursive=True)
    html_files = [f for f in html_files if not _is_build_path(f)]
    has_viewport = False
    for filepath in html_files:
        try:
            with open(filepath) as f:
                if "viewport" in f.read():
                    has_viewport = True
                    break
        except (IOError, UnicodeDecodeError):
            continue

    print(f"  Small fonts (text-xs): {small_fonts} instance(s)")
    print(f"  Viewport meta: {'present' if has_viewport else 'missing — may cause mobile scaling issues'}")

def audit_state_handling(project_dir):
    """Check component state handling coverage."""
    print("\nState Handling Audit:")

    extensions = ["*.tsx", "*.jsx"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if not _is_build_path(f)]

    total_components = 0
    components_with_states = 0
    state_patterns = re.compile(r'Skeleton|Spinner|Loading|isLoading|loading|empty|No\s+\w+\s+found|error|Error|ErrorBoundary|catch\s*\(')

    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()
        except (IOError, UnicodeDecodeError):
            continue
        # Count files that export a component
        if re.search(r'export\s+(?:default\s+)?(?:function|const|class)\s', content):
            total_components += 1
            if state_patterns.search(content):
                components_with_states += 1

    if total_components > 0:
        pct = round(100 * components_with_states / total_components)
        print(f"  {components_with_states}/{total_components} components have state handling ({pct}%)")
    else:
        print("  No components found")

def audit_dark_mode(globals_path):
    """Check dark mode token consistency between :root and .dark."""
    print("\nDark Mode Audit:")

    if not globals_path or not os.path.exists(globals_path):
        print("  No globals.css — skipping")
        return

    try:
        with open(globals_path) as f:
            content = f.read()
    except (IOError, UnicodeDecodeError):
        print("  Could not read globals.css")
        return

    # Extract tokens from :root and .dark blocks
    root_match = re.search(r':root\s*\{([^}]+)\}', content)
    dark_match = re.search(r'\.dark\s*\{([^}]+)\}', content)

    if not root_match:
        print("  No :root block found")
        return

    root_tokens = set(re.findall(r'--([\w-]+):', root_match.group(1)))

    if not dark_match:
        print(f"  Dark mode: not configured ({len(root_tokens)} tokens in :root, no .dark block)")
        return

    dark_tokens = set(re.findall(r'--([\w-]+):', dark_match.group(1)))
    missing = root_tokens - dark_tokens

    print(f"  {len(root_tokens)} tokens in :root, {len(dark_tokens)} in .dark, {len(missing)} missing from .dark")
    if missing:
        for token in sorted(missing)[:10]:
            print(f"    --{token}")
        if len(missing) > 10:
            print(f"    ... and {len(missing) - 10} more")

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
    score = compute_completeness_score(args.dir, globals_path)
    save_audit_history(args.dir, score, {})
    audit_responsive(args.dir)
    audit_state_handling(args.dir)
    audit_dark_mode(globals_path)

if __name__ == "__main__":
    main()
