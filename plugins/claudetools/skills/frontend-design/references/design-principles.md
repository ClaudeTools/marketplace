# Design Principles

Merged from v0 system prompt and interface-design craft philosophy.

---

## Start with Grayscale

Design in grayscale first. Add color last.

This forces proper hierarchy through spacing, contrast, and typography BEFORE relying on color as a crutch. If your interface doesn't work in grayscale, color won't save it — it'll just mask the problem.

**Workflow:**
1. Build the layout with `bg-background`, `text-foreground`, `border-border` only
2. Establish hierarchy through size, weight, spacing, and opacity
3. Verify the squint test passes in grayscale
4. THEN add brand color, accents, and semantic colors
5. Color should REINFORCE hierarchy that already exists, not create it

---

## Color System

Use exactly 3-5 colors total.

- 1 primary brand color appropriate to the product domain
- 2-3 neutrals (white, grays, off-whites, black variants)
- 1-2 accent colors maximum
- NEVER exceed 5 total colors without explicit user permission
- NEVER use purple/violet prominently unless explicitly requested
- If you override a background color, you MUST override its text color for contrast

### Gradient Rules

Avoid gradients unless explicitly asked. If necessary:

- Subtle accents only, never primary elements
- Analogous colors only: blue-to-teal, purple-to-pink, orange-to-red
- NEVER mix opposing temperatures: pink-to-green, orange-to-blue, red-to-cyan
- Maximum 2-3 color stops

## Color Philosophy

Every product exists in a world. That world has colors.

Before reaching for a palette, explore the product's domain. If this product were a physical space, what would you see? What materials, light, objects? A bakery management tool lives in warm flour-dusted surfaces. A trading terminal lives in cool data-dense screens.

Your palette should feel like it came FROM somewhere, not applied TO something.

- Gray builds structure. Color communicates status, action, emphasis, identity
- Unmotivated color is noise. One accent used with intention beats five without thought
- Temperature is one axis. Also consider: quiet/loud, dense/spacious, serious/playful

## Typography

Maximum 2 font families. More fonts create visual chaos and slow loading.

**Four distinct levels:**

- **Heading font** — heavier weight, tight letter-spacing (`tracking-tight`) for presence
- **Body font** — comfortable weight for readability, line-height 1.4-1.6
- **Label font** — medium weight, works at small sizes for UI elements
- **Data font** — monospace with `tabular-nums` for columnar alignment

Minimum 14px for body text. Never use decorative fonts for body text.

```tsx
// layout.tsx — Font setup with CSS variables
import { Inter, JetBrains_Mono } from "next/font/google";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const jetbrains = JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html className={`${inter.variable} ${jetbrains.variable}`}>
      <body className="font-sans">{children}</body>
    </html>
  );
}
```

```ts
// tailwind.config.ts — Font family extension
export default {
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-inter)"],
        mono: ["var(--font-jetbrains)"],
      },
    },
  },
};
```

## Surface & Token Architecture

Every color traces back to primitives: foreground, background, border, brand, semantic.
No raw hex values. No `text-white` or `bg-black`. Everything via design tokens.

### Elevation Hierarchy

```
Level 0: Base background (app canvas)
Level 1: Cards, panels (same visual plane as base)
Level 2: Dropdowns, popovers (floating above)
Level 3: Nested dropdowns, stacked overlays
Level 4: Highest elevation (rare)
```

Dark mode: higher elevation = slightly lighter. Light mode: higher elevation = slightly lighter or uses shadow.

### The Subtlety Principle

Study Vercel, Supabase, Linear — surfaces are barely different but distinguishable.

- Surface jumps: a few percentage points of lightness, not dramatic
- Borders: low opacity (0.05-0.12 alpha for dark mode). Disappear when not looked for, findable when needed
- **Sidebars**: same background as canvas, subtle border for separation
- **Inputs**: slightly darker than surroundings (inset feel)

### Semantic Token Setup

```css
/* globals.css — Token architecture */
:root {
  --background: 0 0% 100%;
  --foreground: 240 10% 3.9%;
  --muted: 240 4.8% 95.9%;
  --muted-foreground: 240 3.8% 46.1%;
  --border: 240 5.9% 90%;
  --border-subtle: 240 5.9% 94%;
  --input: 240 5.9% 88%;
  --primary: 240 5.9% 10%;
  --primary-foreground: 0 0% 98%;
  --accent: 240 4.8% 95.9%;
  --accent-foreground: 240 5.9% 10%;
  --destructive: 0 84.2% 60.2%;
  --ring: 240 5.9% 10%;
  --radius: 0.5rem;
}
```

## Text Hierarchy

Four levels, used consistently:

- **Primary** — default text, highest contrast (`text-foreground`)
- **Secondary** — supporting text, slightly muted (`text-muted-foreground` at ~60% opacity)
- **Tertiary** — metadata, timestamps (`text-muted-foreground` at ~45% opacity)
- **Muted** — disabled, placeholder, lowest contrast

If you are only using two, your hierarchy is too flat.

## Depth Strategies

Choose ONE and commit. Do not mix.

| Strategy | Feel | Use Case |
|---|---|---|
| Borders-only | Clean, technical, dense | Developer tools, utility-focused |
| Subtle shadows | Soft lift, approachable | SaaS apps, consumer products |
| Layered shadows | Premium, dimensional | Finance, enterprise dashboards |
| Surface shifts | Minimal, background tints | Reading apps, minimal interfaces |

### Border Progression

- **Default** — standard borders
- **Subtle** — softer separation
- **Strong** — emphasis, hover states
- **Stronger** — maximum emphasis, focus rings

## Layout

Mobile-first. Enhance for larger screens with responsive prefixes.
Wrap titles and important copy in `text-balance` or `text-pretty` for optimal line breaks.

**Priority:** Flexbox > CSS Grid > Absolute positioning

- Tailwind spacing scale only: `p-4`, `mx-2`, `gap-6` — NO arbitrary values like `p-[16px]`
- Gap classes for spacing, never `space-*` classes
- Never mix margin/padding with gap on the same element
- Wrap titles in `text-balance` or `text-pretty`

## Transitions and Animation

All interactive elements need subtle transitions. Static interfaces feel dead.

```
/* Standard hover transitions */
transition-colors duration-150        /* buttons, links, nav items */
transition-all duration-200 ease-out  /* dropdowns, popovers appearing */
transition-opacity duration-300       /* content swaps, fade in/out */
```

- NEVER use bounce or spring easing in professional interfaces
- NEVER animate layout properties (width, height) — animate opacity and transform instead
- Larger transitions can be slightly longer (200-300ms). Micro-interactions stay fast (100-150ms).
- Use deceleration easing (`ease-out`) for elements entering. Acceleration (`ease-in`) for elements leaving.

## Responsive Patterns

```
/* Common breakpoints */
sm: 640px   /* Phone landscape */
md: 768px   /* Tablet portrait */
lg: 1024px  /* Tablet landscape / small desktop */
xl: 1280px  /* Desktop */

/* Stack to grid */
flex flex-col md:grid md:grid-cols-2 lg:grid-cols-3 gap-6

/* Contained content */
w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8

/* Sidebar to drawer */
/* lg+: visible sidebar. Mobile: hidden, toggle via hamburger */
hidden lg:block  /* sidebar */
block lg:hidden  /* hamburger button */
```

## Clone and Reference Design Handling

When the user asks for a clone or specific design:

- Follow the source as closely as possible
- Use Chrome browser automation (InspectSite) to study the source website if needed
- NEVER create anything malicious or for phishing purposes
- Match layout, spacing, color relationships, and typography hierarchy of the source

## Anti-patterns

- Harsh borders (first thing you see = too strong)
- Dramatic surface jumps between elevation levels
- Inconsistent spacing (clearest sign of no system)
- Mixed depth strategies in the same interface
- Gradients used for decoration rather than meaning
- Multiple accent colors (dilutes focus)
- Different hues for different surfaces (shift lightness only)
- Pure white cards on colored backgrounds
- Raw color classes (`text-white`, `bg-black`) instead of semantic tokens
