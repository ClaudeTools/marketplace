#!/usr/bin/env python3
"""Generate structured extraction prompts for design reproduction.

Takes a description of what's in a screenshot and generates the specific
prompts Claude should use to extract design details systematically.

Can also parse Claude's extraction responses and output design-system.py
compatible arguments.

Usage:
  python3 extract-design-from-image.py prompts              # Print all extraction prompts
  python3 extract-design-from-image.py prompts --region header  # Prompt for specific region
  python3 extract-design-from-image.py parse --colors "#3b82f6 brand, #ffffff bg, #0a0a0a fg"
  python3 extract-design-from-image.py checklist             # Print reproduction checklist
"""
import sys
import argparse
import re

EXTRACTION_PROMPTS = {
    "colors": """Look at this screenshot carefully. List EVERY distinct color you can see.
For each color:
1. Estimate the hex value as precisely as possible
2. Where it appears (e.g., "header background", "primary button", "body text")
3. Usage type: BACKGROUND | TEXT | BORDER | ACCENT | SEMANTIC

Format as a table:
| Hex | Location | Type |
|-----|----------|------|

Be exhaustive — include subtle grays, borders, shadows, and hover states if visible.""",

    "typography": """Analyze all text in this screenshot. For each DISTINCT text style, identify:
1. Approximate font size (in pixels)
2. Font weight (300=light, 400=regular, 500=medium, 600=semibold, 700=bold)
3. Font family: serif, sans-serif, or monospace. If recognizable, name it (Inter, Geist, etc.)
4. Letter spacing: tight (-0.02em), normal, wide (0.05em+)
5. Line height: tight (1.2), normal (1.5), relaxed (1.7)
6. Color (hex estimate)
7. Where this style is used

Format as a table:
| Size | Weight | Family | Spacing | Line-height | Color | Usage |
|------|--------|--------|---------|-------------|-------|-------|""",

    "layout": """Describe the layout structure of this screenshot precisely:

1. **Overall structure**: What is the page layout? (sidebar+content, centered, full-width, split, grid)
2. **Grid**: How many columns? Approximate column widths in px or %.
3. **Container**: Does content have a max-width? Estimate the value.
4. **Spacing between sections**: Estimate vertical gaps between major page sections (in px).
5. **Card/component spacing**: Estimate gaps between repeated elements (in px).
6. **Padding**: Estimate the following:
   - Page-level horizontal padding
   - Section vertical padding
   - Card internal padding
   - Header height
   - Sidebar width (if present)
7. **Alignment**: Is content left-aligned, centered, or justified?

Use specific pixel values, not vague descriptions.""",

    "components": """For each distinct UI component visible in this screenshot, extract:

**Buttons:**
- Height, horizontal padding, border-radius
- Background color, text color, border (if any)
- Font size and weight

**Cards/Containers:**
- Padding (all sides), border-radius
- Background color, border color and width
- Shadow (spread, blur, color — or "none")

**Inputs/Form controls:**
- Height, padding, border-radius
- Background color, border color and width
- Placeholder text color

**Navigation:**
- Item height, horizontal padding
- Active/selected state treatment
- Hover state (if visible)

**Badges/Tags:**
- Height, padding, border-radius
- Background and text color

Format each as a specification block.""",

    "depth": """What depth strategy does this design use?

Look for:
- **Borders only** (no shadows, structure defined by borders)
- **Subtle shadows** (gentle drop shadows on cards/buttons)
- **Layered shadows** (multiple shadow layers, dramatic depth)
- **Surface shifts** (no borders or shadows, hierarchy from background color changes)

Also note:
- Border color and opacity (are they harsh or subtle?)
- Shadow values if present (estimate: offset, blur, spread, color/opacity)
- How elevation is communicated (higher = lighter? more shadow? both?)""",
}

CHECKLIST = """## Reproduction Checklist

Before each comparison pass, verify:

### Pass 1: Structure (~70% match target)
- [ ] Overall layout matches (sidebar, header, content areas)
- [ ] Grid columns and proportions correct
- [ ] Container max-width matches
- [ ] Major sections present in correct order
- [ ] Navigation structure matches

### Pass 2: Visual System (~85% match target)
- [ ] Background colors match (body, cards, header, sidebar)
- [ ] Text colors match (primary, secondary, muted)
- [ ] Brand/accent color correct
- [ ] Font families loaded and applied
- [ ] Font sizes match the extracted type scale
- [ ] Spacing between sections matches
- [ ] Card padding matches
- [ ] Border radius matches

### Pass 3: Details (~93%+ match target)
- [ ] Border colors and widths match
- [ ] Shadows match (or absence of shadows)
- [ ] Button styles match (height, padding, radius, colors)
- [ ] Input styles match
- [ ] Icon sizes and colors match
- [ ] Hover states present on interactive elements
- [ ] Focus rings styled
- [ ] Active/selected states styled
- [ ] Empty states handled
- [ ] Mobile responsive behavior matches

### Final: Pixel Diff
- [ ] Run screenshot-compare.sh with reference and implementation
- [ ] Overall match >93%
- [ ] No single region below 85%
- [ ] Diff image reviewed — remaining differences are acceptable
"""

def cmd_prompts(args):
    if args.region:
        region = args.region.lower()
        if region in EXTRACTION_PROMPTS:
            print(EXTRACTION_PROMPTS[region])
        else:
            print(f"Unknown region: {region}")
            print(f"Available: {', '.join(EXTRACTION_PROMPTS.keys())}")
    else:
        for name, prompt in EXTRACTION_PROMPTS.items():
            print(f"### {name.upper()} EXTRACTION")
            print()
            print(prompt)
            print()
            print("---")
            print()

def cmd_parse(args):
    """Parse extracted color values into design-system.py arguments."""
    if not args.colors:
        print("Provide --colors with extracted values")
        print('Example: --colors "#3b82f6 brand, #ffffff bg, #0a0a0a fg"')
        return

    brand = bg = fg = ""
    for part in args.colors.split(","):
        part = part.strip().lower()
        hex_match = re.search(r'#[0-9a-f]{6}', part)
        if not hex_match:
            continue
        color = hex_match.group(0)
        if "brand" in part or "primary" in part or "accent" in part:
            brand = color
        elif "bg" in part or "background" in part or "canvas" in part:
            bg = color
        elif "fg" in part or "foreground" in part or "text" in part or "body" in part:
            fg = color

    if brand:
        cmd = f'python3 design-system.py --brand "{brand}"'
        if bg:
            cmd += f' --bg "{bg}"'
        if fg:
            cmd += f' --fg "{fg}"'
        print(f"Design system command:")
        print(f"  {cmd}")
        print()
        print(f"Contrast check:")
        if fg and bg:
            print(f'  python3 color-system.py contrast --fg "{fg}" --bg "{bg}"')
        if brand and bg:
            print(f'  python3 color-system.py contrast --fg "{brand}" --bg "{bg}"')
    else:
        print("Could not identify brand color. Label one color as 'brand' or 'primary'.")

def cmd_checklist(args):
    print(CHECKLIST)

def main():
    parser = argparse.ArgumentParser(description="Design extraction helper for clone/reproduction")
    subparsers = parser.add_subparsers(dest="command")

    p_prompts = subparsers.add_parser("prompts", help="Print extraction prompts")
    p_prompts.add_argument("--region", help="Specific region: colors, typography, layout, components, depth")

    p_parse = subparsers.add_parser("parse", help="Parse extracted values into script args")
    p_parse.add_argument("--colors", help='Extracted colors: "#hex role, #hex role, ..."')

    p_check = subparsers.add_parser("checklist", help="Print reproduction checklist")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    {"prompts": cmd_prompts, "parse": cmd_parse, "checklist": cmd_checklist}[args.command](args)

if __name__ == "__main__":
    main()
