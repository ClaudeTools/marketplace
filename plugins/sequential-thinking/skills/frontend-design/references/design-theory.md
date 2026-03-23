# Design Theory

Foundational principles that make interfaces feel intentional rather than accidental.

---

## Gestalt Principles

How humans perceive visual grouping. Use these to create clear structure WITHOUT explicit borders.

**Proximity:** Elements close together are perceived as a group. Spacing creates grouping more naturally than borders. Use tighter gaps within groups, larger gaps between groups.

**Similarity:** Elements that look alike are perceived as related. Consistent styling (color, size, shape) signals "these belong together." Inconsistency signals boundaries.

**Closure:** The mind completes incomplete shapes. You don't need to draw every border — a background shift or shadow is enough to define a region.

**Continuity:** The eye follows smooth paths. Align elements along invisible axes. Broken alignment feels random even if technically correct.

**Figure-Ground:** Elements are perceived as either foreground (object) or background (surface). Use elevation, color, and contrast to establish what's "on top."

---

## Eye Tracking Patterns

Research-backed patterns for how people scan interfaces.

### F-Pattern
For text-heavy, content-dense pages (dashboards, settings, documentation):
- Users scan across the top (navigation, header)
- Move down the left side
- Scan across again at points of interest
- **Implication:** Put primary actions and labels on the left. Key information at the top.

### Z-Pattern
For minimal, marketing-oriented pages (landing pages, hero sections):
- Top-left (logo) → Top-right (CTA) → Bottom-left (supporting content) → Bottom-right (final CTA)
- **Implication:** Place the primary CTA at top-right or bottom-right.

### Hierarchy by Position
- **Top-left:** First seen, highest authority (navigation, logo)
- **Center:** Focal point for primary content
- **Bottom-right:** Terminal position, ideal for primary actions
- **Below the fold:** Only seen if above-fold content earns attention

---

## Visual Weight and Balance

Every element has visual weight determined by:
- **Size:** Larger = heavier
- **Color:** Saturated/dark = heavier than muted/light
- **Contrast:** High contrast = heavier
- **Density:** Dense content (text, data) = heavier than whitespace
- **Position:** Elements at edges feel heavier than centered ones

### Balance Strategies
- **Symmetrical:** Equal weight on both sides. Feels formal, stable. For: settings, forms.
- **Asymmetrical:** Unequal but balanced. Feels dynamic, modern. For: dashboards, marketing.
- **Radial:** Weight distributed from a center point. For: hero sections, focus states.

A heavy sidebar needs visual counterweight in the content area (larger headings, featured content, color accents).

---

## Information Hierarchy

5 techniques for establishing what's important. Professional interfaces use 3-4 simultaneously:

1. **Size** — Larger elements attract attention first
2. **Color/Contrast** — Saturated or high-contrast elements stand out
3. **Weight** — Bold text, filled icons, solid backgrounds
4. **Position** — Top-left and center are seen first
5. **Whitespace** — Isolated elements with surrounding space gain importance

**WRONG:** Using only size to create hierarchy (big heading, smaller subheading, small text)
**CORRECT:** Combining size + weight + color + whitespace (large bold heading with generous top padding, medium secondary text in a muted color, small metadata with reduced opacity)

---

## Vertical Rhythm

Consistent vertical spacing based on a baseline grid creates visual harmony.

### How It Works
Choose a baseline unit (4px or 8px). ALL vertical measurements must be multiples:
- Line heights: multiples of baseline
- Margins/padding: multiples of baseline
- Component heights: multiples of baseline
- Gaps between sections: multiples of baseline

### Why It Matters
When everything aligns to the same grid, the page feels "right" even if the viewer can't articulate why. When values are arbitrary (13px here, 17px there), it creates subtle visual noise.

```
/* 4px baseline grid */
--space-1: 4px;    /* micro: icon gaps, inline spacing */
--space-2: 8px;    /* component: button padding, card gaps */
--space-3: 12px;   /* within: form field spacing */
--space-4: 16px;   /* standard: paragraph spacing */
--space-6: 24px;   /* section: between card groups */
--space-8: 32px;   /* major: between page sections */
--space-12: 48px;  /* page: header/footer padding */
--space-16: 64px;  /* hero: dramatic vertical spacing */
```

---

## Modular Scale

A sequence of proportionally related numbers for sizing type, spacing, and elements.

### Common Ratios
| Name | Ratio | Feel |
|------|-------|------|
| Minor second | 1.067 | Very tight, subtle hierarchy |
| Major second | 1.125 | Tight, professional |
| Minor third | 1.200 | Moderate, balanced |
| **Major third** | **1.250** | **Comfortable — most popular** |
| Perfect fourth | 1.333 | Generous, clear hierarchy |
| Golden ratio | 1.618 | Dramatic, editorial |

### Applying a Scale
Given base=16px and ratio=1.25:
```
xs:    10px  (16 / 1.25²)
sm:    13px  (16 / 1.25)
base:  16px
lg:    20px  (16 × 1.25)
xl:    25px  (16 × 1.25²)
2xl:   31px  (16 × 1.25³)
3xl:   39px  (16 × 1.25⁴)
```

Use the type-scale.py script to compute scales with baseline grid snapping:
`python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/type-scale.py scale --base 16 --ratio major-third --grid 4`

---

## Fluid Typography

Instead of jumping between fixed sizes at breakpoints, font sizes smoothly scale with viewport width.

CSS clamp() formula: `font-size: clamp(min, preferred, max)`

```css
/* Heading: 24px on mobile → 40px on desktop */
font-size: clamp(1.5rem, 1rem + 2vw, 2.5rem);

/* Body: stays 16px but can grow slightly */
font-size: clamp(1rem, 0.95rem + 0.25vw, 1.125rem);
```

Use the type-scale.py script: `python3 type-scale.py fluid --min 24 --max 40`

---

## Whitespace Rhythm Categories

Not all spacing is equal. Different contexts need different amounts:

| Category | Purpose | Typical Range | Example |
|----------|---------|---------------|---------|
| **Micro** | Within elements | 2-8px | Icon-to-label gap, inline badge padding |
| **Component** | Between sibling elements | 8-16px | Button group gap, form field spacing |
| **Section** | Between logical groups | 24-48px | Card grid gap, form section divider |
| **Page** | Between major regions | 48-96px | Header-to-hero, features-to-footer |

Use these categories to choose the RIGHT token from the spacing scale, not just any grid-valid value.

```css
/* Spacing categories mapped to tokens */
--space-micro: var(--space-1);     /* 4px */
--space-component: var(--space-3); /* 12px */
--space-section: var(--space-6);   /* 24px */
--space-page: var(--space-12);     /* 48px */
```

## Interactive Element Harmony

Buttons, inputs, selects, and date pickers MUST have the same height at each size tier. When heights differ, forms look broken.

```
Size    Font    Padding   Border   Total (on 4px grid)
sm      12px    6px × 2   1px × 2  28px
md      16px    8px × 2   1px × 2  34px → snap to 36px
lg      20px    10px × 2  1px × 2  42px → snap to 44px (also meets touch target)
```

Use `design-system.py` which computes these automatically as `--control-height-sm/md/lg`.

## The 60-30-10 Rule

Color distribution for visual balance:
- **60%** — Dominant color (background, large surfaces)
- **30%** — Secondary color (cards, sections, supporting elements)
- **10%** — Accent color (CTAs, highlights, brand touches)

This prevents color chaos. Even with 5 colors in your palette, distribution should follow this ratio.
