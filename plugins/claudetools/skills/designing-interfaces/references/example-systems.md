# Example Design Systems

Two complete systems showing how all decisions connect. Study the THINKING, not the values.

---

## Example 1: Warmth & Approachability

**For:** Collaborative apps, consumer products, content platforms
**Feel:** Like a well-organized kitchen — warm, inviting, personal

### Tokens
```css
:root {
  /* Warm foundation — stone instead of gray */
  --background: 30 6% 98%;
  --background-subtle: 30 6% 96%;
  --foreground: 28 8% 12%;
  --foreground-secondary: 28 6% 38%;

  /* Borders: warm, very subtle */
  --border: 28 6% 90%;

  /* Brand: warm amber */
  --brand: 25 95% 53%;

  /* Generous spacing */
  --space-base: 4px;

  /* Soft radius */
  --radius: 0.5rem;
  --radius-lg: 0.75rem;

  /* Subtle shadows (depth strategy) */
  --shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
}
```

### Component Patterns
| Component | Height | Padding | Radius | Font |
|-----------|--------|---------|--------|------|
| Button | 40px | 12px 20px | 8px | 15px/500 |
| Input | 44px | 12px 16px | 8px | 16px/400 |
| Card | auto | 20px | 12px | — |

### Key Decisions
- **Stone grays** (not cool slate) — warmth in every neutral
- **Generous padding** (20px cards, 12px inputs) — space to breathe
- **Subtle shadows** not borders — soft, approachable feel
- **Inter font** — geometric but slightly warm
- **Amber accent** — feels natural, not corporate

### What to Avoid
- Tight spacing (feels clinical, not warm)
- Sharp corners (feels technical, not friendly)
- Cool blues (contradicts warm foundation)
- Dense data tables (this isn't a power-user tool)

---

## Example 2: Precision & Density

**For:** Developer tools, admin dashboards, data-heavy applications
**Feel:** Like a well-organized workshop — everything has a place

### Tokens
```css
:root {
  /* Cool foundation — slate */
  --background: 222 14% 100%;
  --background-subtle: 222 14% 98%;
  --foreground: 222 47% 11%;
  --foreground-secondary: 215 16% 47%;

  /* Borders: the primary structural tool */
  --border: 214 14% 90%;

  /* Brand: precise blue */
  --brand: 217 91% 60%;

  /* Compact spacing */
  --space-base: 4px;

  /* Sharp radius */
  --radius: 0.25rem;
  --radius-lg: 0.375rem;

  /* Borders-only (no shadows) */
  --shadow: none;
}
```

### Component Patterns
| Component | Height | Padding | Radius | Font |
|-----------|--------|---------|--------|------|
| Button | 32px | 8px 12px | 4px | 13px/500 |
| Input | 32px | 6px 8px | 4px | 13px/400 |
| Card | auto | 12px | 6px | — |
| Table Cell | auto | 8px 12px | 0 | 13px tabular-nums |

### Key Decisions
- **Borders-only** — information density over visual lift
- **Compact sizing** (32px controls) — more data per screen
- **System fonts** — performance, native feel, no loading delay
- **Monospace for data** — tabular-nums for number alignment
- **Sharp radius** (4px) — technical precision

### What to Avoid
- Rounded corners > 8px (too playful for data tools)
- Warm colors (contradicts precision)
- Large padding (wastes screen real estate)
- Decorative elements (distract from data)
- Shadows (add visual weight without information value)

---

## How to Use These Examples

1. Read your product's intent — is it closer to warmth or precision?
2. Use the matching example as a STARTING POINT for token values
3. Adjust based on your specific domain exploration
4. Run `design-system.py` with the adjusted values
5. The example teaches the APPROACH — your product should look unique
