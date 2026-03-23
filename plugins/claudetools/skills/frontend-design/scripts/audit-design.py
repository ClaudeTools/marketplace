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
    responsive_files = 0
    files_with_breakpoints = set()
    fixed_widths = 0
    overflow_hidden = 0
    touch_targets_small = 0

    breakpoint_re = re.compile(r'\b(?:sm|md|lg|xl|2xl):')
    fixed_width_re = re.compile(r'\bw-\[\d{4,}px\]|\bwidth:\s*\d{4,}px')
    overflow_re = re.compile(r'\boverflow-hidden\b')
    small_interactive_re = re.compile(r'(?:w-[456]|h-[456])\b')

    for filepath in files:
        try:
            with open(filepath) as f:
                content = f.read()
                small_fonts += len(re.findall(r'text-xs\b', content))

                if breakpoint_re.search(content):
                    files_with_breakpoints.add(filepath)

                fixed_widths += len(fixed_width_re.findall(content))
                overflow_hidden += len(overflow_re.findall(content))

                # Check for small interactive elements
                for i, line in enumerate(content.split('\n'), 1):
                    if small_interactive_re.search(line):
                        if re.search(r'button|Button|<a |<Link|onClick|href|role="button"', line, re.IGNORECASE):
                            touch_targets_small += 1
        except (IOError, UnicodeDecodeError):
            continue

    responsive_files = len(files_with_breakpoints)
    total_files = len(files)

    # Check for viewport meta in layout/HTML files
    html_files = globmod.glob(os.path.join(project_dir, "**", "*.html"), recursive=True)
    html_files += globmod.glob(os.path.join(project_dir, "**/layout.tsx"), recursive=True)
    html_files += globmod.glob(os.path.join(project_dir, "**/layout.jsx"), recursive=True)
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

    # Check for container queries (modern responsive pattern)
    css_files = globmod.glob(os.path.join(project_dir, "**", "*.css"), recursive=True)
    css_files = [f for f in css_files if not _is_build_path(f)]
    container_queries = 0
    for filepath in css_files + files:
        try:
            with open(filepath) as f:
                container_queries += len(re.findall(r'@container|container-type', f.read()))
        except (IOError, UnicodeDecodeError):
            continue

    # Check for mobile-safe viewport units (svh/dvh vs vh)
    unsafe_vh = 0
    safe_vh = 0
    for filepath in files + css_files:
        try:
            with open(filepath) as f:
                content = f.read()
                unsafe_vh += len(re.findall(r'100vh\b', content))
                safe_vh += len(re.findall(r'100[sd]vh\b', content))
        except (IOError, UnicodeDecodeError):
            continue

    # Report
    print(f"  Viewport meta: {'present' if has_viewport else 'MISSING — mobile scaling broken'}")

    if total_files > 0:
        pct = round(100 * responsive_files / total_files)
        print(f"  Responsive breakpoints: {responsive_files}/{total_files} files use sm:/md:/lg: ({pct}%)")
        if pct < 20:
            print(f"    LOW — consider adding responsive variants to layout components")
    else:
        print(f"  Responsive breakpoints: no component files found")

    if container_queries > 0:
        print(f"  Container queries: {container_queries} usage(s) — modern responsive pattern")

    print(f"  Small fonts (text-xs): {small_fonts} instance(s){' — may be unreadable on mobile' if small_fonts > 10 else ''}")

    if fixed_widths > 0:
        print(f"  Fixed widths (>999px): {fixed_widths} instance(s) — may overflow on mobile")

    if touch_targets_small > 0:
        print(f"  Small touch targets: {touch_targets_small} interactive element(s) with w-4/5/6 — min 44px recommended")

    if unsafe_vh > 0 and safe_vh == 0:
        print(f"  Viewport units: {unsafe_vh} uses of 100vh — use 100svh/100dvh to avoid mobile address bar issues")

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

def audit_class_conflicts(project_dir):
    """Detect conflicting Tailwind utility classes in the same className string."""
    print("\nTailwind Class Conflict Audit:")

    extensions = ["*.tsx", "*.jsx", "*.vue", "*.svelte", "*.astro"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if not _is_build_path(f)]

    # Define conflict groups — utilities in the same group with different values conflict
    conflict_prefixes = [
        "mt-", "mb-", "ml-", "mr-", "mx-", "my-", "m-",
        "pt-", "pb-", "pl-", "pr-", "px-", "py-", "p-",
        "w-", "h-", "min-w-", "min-h-", "max-w-", "max-h-",
        "text-", "bg-", "border-", "rounded-",
        "gap-", "gap-x-", "gap-y-",
        "flex-", "grid-cols-", "grid-rows-",
        "font-", "leading-", "tracking-",
        "z-", "opacity-",
    ]

    # Extract className strings and check for conflicts
    classname_re = re.compile(r'(?:className|class)=[\"\']([^\"\']+)[\"\']|(?:className|class)=\{[`\"]([^`\"]+)[`\"]\}')
    conflicts = []

    for filepath in files:
        try:
            with open(filepath) as f:
                for i, line in enumerate(f, 1):
                    for match in classname_re.finditer(line):
                        classes = (match.group(1) or match.group(2) or "").split()
                        # Group classes by prefix
                        for prefix in conflict_prefixes:
                            matching = [c for c in classes if c.startswith(prefix) and not c.startswith(prefix[:-1] + "[")] # exclude arbitrary values
                            # Filter out responsive prefixes (sm:mt-4 and mt-2 aren't conflicts)
                            matching = [c for c in matching if ":" not in c]
                            if len(matching) > 1:
                                conflicts.append(f"  {os.path.basename(filepath)}:{i}: {' '.join(matching)}")
        except (IOError, UnicodeDecodeError):
            continue

    if conflicts:
        print(f"  {len(conflicts)} conflict(s) found:")
        for c in conflicts[:15]:
            print(c)
        if len(conflicts) > 15:
            print(f"  ... and {len(conflicts) - 15} more")
    else:
        print("  No conflicting utility classes detected")

def audit_zindex(project_dir):
    """Audit z-index usage for sprawl and consistency."""
    print("\nZ-Index Audit:")

    extensions = ["*.tsx", "*.jsx", "*.vue", "*.svelte", "*.astro", "*.css"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if not _is_build_path(f)]

    zindex_values = {}  # value -> list of file:line
    zindex_re = re.compile(r'z-(\d+)\b|z-\[(\d+)\]|z-index:\s*(\d+)')

    for filepath in files:
        try:
            with open(filepath) as f:
                for i, line in enumerate(f, 1):
                    for match in zindex_re.finditer(line):
                        val = match.group(1) or match.group(2) or match.group(3)
                        if val:
                            key = int(val)
                            if key not in zindex_values:
                                zindex_values[key] = []
                            zindex_values[key].append(f"{os.path.basename(filepath)}:{i}")
        except (IOError, UnicodeDecodeError):
            continue

    total_uses = sum(len(v) for v in zindex_values.values())
    distinct = len(zindex_values)

    if distinct == 0:
        print("  No z-index usage found")
        return

    print(f"  {total_uses} total uses across {distinct} distinct values: {sorted(zindex_values.keys())}")

    if distinct > 6:
        print(f"  WARNING: {distinct} distinct z-index values is excessive — define a z-index scale in your design tokens")
    elif distinct > 3:
        print(f"  Consider documenting your z-index scale for consistency")
    else:
        print(f"  Z-index usage looks manageable")

def audit_unused_tokens(project_dir, globals_path):
    """Find CSS custom properties defined in globals.css but never referenced in components."""
    print("\nUnused Token Audit:")

    if not globals_path or not os.path.exists(globals_path):
        print("  No globals.css — skipping")
        return

    try:
        with open(globals_path) as f:
            content = f.read()
    except (IOError, UnicodeDecodeError):
        print("  Could not read globals.css")
        return

    # Extract all token names defined in globals.css
    defined_tokens = set(re.findall(r'--([\w-]+)\s*:', content))
    if not defined_tokens:
        print("  No tokens defined")
        return

    # Scan all component and CSS files for token references
    extensions = ["*.tsx", "*.jsx", "*.ts", "*.js", "*.vue", "*.svelte", "*.astro", "*.css"]
    files = []
    for ext in extensions:
        files.extend(globmod.glob(os.path.join(project_dir, "**", ext), recursive=True))
    files = [f for f in files if not _is_build_path(f)]

    # Collect all referenced tokens across the project
    referenced_tokens = set()
    token_ref_re = re.compile(r'var\(--([a-z][\w-]*)')
    hsl_ref_re = re.compile(r'hsl\(var\(--([a-z][\w-]*)')
    # Also catch Tailwind/shadcn patterns like bg-[hsl(var(--primary))]
    tw_ref_re = re.compile(r'--([a-z][\w-]*)')

    for filepath in files:
        if os.path.abspath(filepath) == os.path.abspath(globals_path):
            continue  # Skip the definition file itself
        try:
            with open(filepath) as f:
                file_content = f.read()
                for match in token_ref_re.finditer(file_content):
                    referenced_tokens.add(match.group(1))
                for match in hsl_ref_re.finditer(file_content):
                    referenced_tokens.add(match.group(1))
        except (IOError, UnicodeDecodeError):
            continue

    # Also check references within globals.css itself (tokens referencing other tokens)
    for match in token_ref_re.finditer(content):
        referenced_tokens.add(match.group(1))

    unused = defined_tokens - referenced_tokens
    # Filter out common internal/system tokens that are expected to be defined but referenced indirectly
    system_tokens = {"radius", "ring", "chart-1", "chart-2", "chart-3", "chart-4", "chart-5", "sidebar-ring"}
    unused = {t for t in unused if not any(t.startswith(p) for p in ("chart-",)) and t not in system_tokens}

    print(f"  {len(defined_tokens)} defined, {len(referenced_tokens)} referenced, {len(unused)} unused")
    if unused:
        for token in sorted(unused)[:15]:
            print(f"    --{token}")
        if len(unused) > 15:
            print(f"    ... and {len(unused) - 15} more")
        print(f"  Consider removing unused tokens or adding references")
    else:
        print("  All tokens are referenced — clean token system!")

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
    audit_class_conflicts(args.dir)
    audit_zindex(args.dir)
    audit_unused_tokens(args.dir, globals_path)

if __name__ == "__main__":
    main()
