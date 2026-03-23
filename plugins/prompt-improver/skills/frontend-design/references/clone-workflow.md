# Clone & Reproduction Workflow

How to faithfully reproduce an existing design from a URL, screenshot, or mockup.

---

## The Problem

Claude's vision gives a broad impression of images but misses precise details — spacing values, exact colors, font sizes, border radii. Saying "reproduce this screenshot" yields 60-70% fidelity. The remaining 30% requires a structured extraction + iterative comparison loop.

---

## Step 1: Capture the Reference

### From a URL
Use Chrome automation to screenshot at a SPECIFIC viewport:
```
Screenshot at 1440x900 (desktop reference)
Screenshot at 390x844 (mobile reference — iPhone 14 Pro dimensions)
```
Save both as reference images. These are your ground truth.

### From a User-Provided Image
The user pastes or attaches a screenshot/mockup. Save it with known dimensions.

### From a Private/Auth-Protected Page
Ask the user to screenshot it themselves and provide the image. We cannot access authenticated pages.

---

## Step 2: Structured Detail Extraction

Do NOT just "look at" the image. Use the extraction script for systematic, focused prompts:

```bash
# Print ALL extraction prompts (colors, typography, layout, components, depth)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-design-from-image.py prompts

# Or target a specific area
python3 extract-design-from-image.py prompts --region colors
python3 extract-design-from-image.py prompts --region typography
python3 extract-design-from-image.py prompts --region layout
python3 extract-design-from-image.py prompts --region components
python3 extract-design-from-image.py prompts --region depth
```

Show the screenshot to Claude with EACH prompt separately. Do not combine — one prompt per extraction pass. Each prompt forces Claude to enumerate specific values instead of giving vague impressions.

---

## Step 3: Build the Design System First

From extracted values, generate the design system BEFORE writing components:

```bash
# Parse extracted colors into design-system.py arguments
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-design-from-image.py \
  parse --colors "#3b82f6 brand, #ffffff bg, #0a0a0a fg"
# Outputs the exact design-system.py command to run

# Generate the complete token system
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py \
  --brand "#extracted" --bg "#extracted" --fg "#extracted" \
  --ratio <closest-matching-ratio> --grid 4 > globals.css
```

Write globals.css and tailwind.config BEFORE any components.

---

## Step 4: Build Component by Component

Build in this order:
1. **Layout shell** — page structure, navigation, sidebar
2. **Repeated components** — cards, list items, table rows (build one, reuse)
3. **Unique sections** — hero, footer, special content areas
4. **Details** — icons, badges, micro-interactions

For each component, reference the SPECIFIC extracted values from Step 2.

---

## Step 5: Iterative Comparison Loop

This is the critical quality step. After building:

### Visual Comparison
1. Start dev server: `pnpm dev`
2. Screenshot your implementation at the SAME viewport dimensions as the reference
3. Place reference and implementation side by side
4. Compare region by region — use Chrome zoom tool for detail inspection

### Structured Diff Prompt
Show Claude BOTH images (reference + implementation) and ask:

"Compare these two screenshots. The first is the reference design, the second is my implementation. For each region of the page (header, hero, features, footer, etc.):
1. Rate the match: EXACT / CLOSE / DIFFERENT
2. List specific differences: spacing, colors, font sizes, alignment, borders, shadows
3. Provide the CSS fix for each difference"

### Automated Comparison Script
```bash
# Full pixel-level comparison with region analysis
bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/screenshot-compare.sh \
  reference.png implementation.png --output diff.png

# Outputs: overall match %, per-quadrant scores, visual diff image
# Requires ImageMagick (sudo apt install imagemagick)
```

### Iteration Target
Use the checklist to track progress:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-design-from-image.py checklist
```

- **Pass 1**: Layout structure (~70% match) — grid, sections, navigation
- **Pass 2**: Visual system (~85% match) — colors, fonts, spacing
- **Pass 3**: Details (~93%+ match) — borders, shadows, states
- **Remaining ~5%**: Font rendering differences (acceptable)

---

## Step 6: What to Clone vs What to Adapt

**Clone exactly:**
- Layout structure and proportions
- Color palette and relationships
- Typography hierarchy and sizing
- Spacing rhythm and density
- Border and shadow treatment

**Adapt for the user's needs:**
- Brand colors (if different from reference)
- Content (use the user's real content)
- Logo and images
- Specific business logic

**Never clone:**
- Copyrighted content verbatim
- Anything for phishing or deception
- Paywalled or proprietary design system source code

---

## Common Clone Failures

**Spacing is off:** Most common issue. Extract spacing VALUES, don't eyeball them. Check: is everything on a 4px grid?

**Colors are close but not right:** Use the color extraction prompt specifically. Check the hex values, don't guess "blue-ish."

**Typography feels different:** Font family matters more than you think. If the reference uses Inter and you use system fonts, it WILL look different. Match the exact font.

**Border radius inconsistent:** Some elements rounded, others sharp. Extract the radius scale from the reference and apply consistently.

**Shadows missing or wrong:** Shadows are subtle and easy to miss. Look specifically for card shadows, button shadows, and dropdown shadows.
