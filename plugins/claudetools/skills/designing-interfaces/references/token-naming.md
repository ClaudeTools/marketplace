# Token Naming

Consistent naming makes tokens discoverable, understandable, and scalable. Follow the semantic naming system.

---

## Naming Architecture

Tokens exist in three layers:

### 1. Primitive Tokens (Raw Values)
NEVER used directly in components. They're the palette:
```css
--blue-500: 217 91% 60%;
--gray-100: 220 14% 96%;
```

### 2. Semantic Tokens (Purpose-Based)
Used in components. They describe WHAT, not WHICH:
```css
--background: var(--gray-100);       /* Not --gray-100 */
--foreground: var(--gray-900);       /* Not --dark-text */
--brand: var(--blue-500);            /* Not --primary-blue */
--destructive: var(--red-500);       /* Not --error-red */
```

### 3. Component Tokens (Specific)
Optionally, for components that need unique values:
```css
--button-height-sm: 28px;
--input-border: var(--control-border);
--card-padding: var(--space-4);
```

---

## Naming Rules

### Use Purpose, Not Appearance
```
WRONG:  --blue-button, --light-bg, --dark-text, --big-heading
CORRECT: --brand, --background, --foreground, --text-2xl
```

### Use Scale Position, Not Pixel Values
```
WRONG:  --space-16px, --radius-8px, --font-14
CORRECT: --space-4, --radius-md, --text-sm
```

### Use Consistent Hierarchy Suffixes
```
--background           (default)
--background-subtle    (less prominent)
--background-muted     (even less)
--background-emphasis  (more prominent)
```

Pattern: `{category}` then `{category}-{modifier}`

### Standard Modifiers
| Modifier | Meaning |
|----------|---------|
| subtle | Less prominent |
| muted | Much less prominent |
| emphasis | More prominent |
| strong | Higher intensity |
| stronger | Maximum intensity |
| foreground | Text color on this surface |

---

## Token Categories

| Category | Tokens | Purpose |
|----------|--------|---------|
| `--background-*` | 4 levels | Surface colors |
| `--foreground-*` | 4 levels | Text colors |
| `--border-*` | 4 levels | Edge colors |
| `--brand-*` | brand, foreground, muted | Brand identity |
| `--accent-*` | 1-3 accents | UI variation |
| `--destructive-*` | color, foreground | Error/delete |
| `--warning-*` | color, foreground | Caution |
| `--success-*` | color, foreground | Confirmation |
| `--info-*` | color, foreground | Information |
| `--control-*` | bg, border, focus | Form controls |
| `--chart-*` | 1-6 | Data visualization |
| `--brand-50` to `--brand-950` | 11 shades | Brand scale |
| `--text-*` | xs through 4xl | Type scale |
| `--space-*` | 1 through 64 | Spacing scale |
| `--radius-*` | sm, default, lg, xl | Corner rounding |
| `--shadow-*` | sm, default, md, lg | Elevation |
| `--z-*` | base through toast | Stacking |
| `--duration-*` | fast, normal, slow | Animation timing |
| `--ease-*` | in, out, in-out | Animation curves |
| `--measure-*` | narrow, default, wide | Content width |
| `--control-height-*` | sm, md, lg | Button/input heights |

---

## Dark Mode Tokens

Same names, different values in `.dark` selector. Components NEVER reference mode:
```css
/* Components use semantic names — dark mode is automatic */
<div className="bg-background text-foreground border-border">
```

NEVER do this:
```tsx
<div className={isDark ? "bg-gray-900" : "bg-white"}>
```
