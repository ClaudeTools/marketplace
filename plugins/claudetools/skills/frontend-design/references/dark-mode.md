# Dark Mode

Dark mode is not inversion. It requires different rules for surfaces, borders, colors, and contrast.

---

## Implementation Strategy

### Class-Based (Recommended)
```tsx
// tailwind.config.ts
darkMode: "class"

// Toggle: add/remove "dark" class on <html>
document.documentElement.classList.toggle("dark");
```

Use class-based over media queries — gives users control. Store preference in localStorage or cookie.

### CSS Variables Approach
Define light and dark values in globals.css using `.dark` selector:
```css
:root { --background: 0 0% 100%; }
.dark { --background: 0 0% 4%; }
```

Components reference `hsl(var(--background))` and automatically adapt.

---

## Dark Mode Rules

### Surfaces
- Higher elevation = slightly LIGHTER (opposite of light mode)
- Base: very dark (3-5% lightness)
- Each step: +3-4% lightness
- NEVER use pure black (#000000) — use near-black with subtle hue tint from brand

### Borders
- More important in dark mode (shadows are less visible)
- Use slightly more opacity than light mode (0.08-0.15 vs 0.05-0.10)
- Light borders on dark surfaces: use white at low opacity, not gray

### Colors
- Semantic colors need slight DESATURATION (red, green, yellow are harsh at full saturation on dark)
- Brand color may need lightness boost (+5-10%) to maintain visibility
- Success green: use #4ade80 (lighter) not #22c55e (darker)
- Error red: use #f87171 (lighter) not #ef4444 (darker)

### Text
- Primary text: 92-96% lightness (not pure white — too harsh)
- Secondary: 70-75% lightness
- Muted: 35-50% lightness
- NEVER use the same foreground values as light mode inverted

### Images and Media
- Consider `filter: brightness(0.9)` on images to reduce glare
- SVG icons: ensure they use currentColor, not hardcoded fills
- Borders around images become more important (content floats without them)

### Contrast
- WCAG requirements still apply — check contrast ratios for dark mode separately
- Run: `python3 color-system.py audit --brand "<hex>" --bg "<dark-bg>" --fg "<dark-fg>"`

---

## Common Dark Mode Mistakes

**WRONG:** Pure black background (#000000)
**CORRECT:** Near-black with brand hue tint (e.g., #0a0a0f for blue brand)

**WRONG:** Same saturated colors as light mode
**CORRECT:** Desaturated/lighter variants for dark backgrounds

**WRONG:** Relying on shadows for elevation
**CORRECT:** Use surface lightness shifts + borders for dark mode elevation

**WRONG:** Only testing light mode, adding dark as afterthought
**CORRECT:** Design both simultaneously — dark mode is 50% of your users

---

## Automatic Dark Mode with design-system.py

```bash
python3 design-system.py --theme midnight
# Outputs both :root (light) and .dark {} sections
# Dark values are computed from color science, not hardcoded
```
