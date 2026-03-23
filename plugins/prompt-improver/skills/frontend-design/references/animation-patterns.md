# Animation Patterns

Motion adds life to interfaces. Used well, it's invisible. Used poorly, it's annoying.

---

## Principles

1. **Motion serves function** — it communicates, confirms, or guides. Never decorates.
2. **Fast by default** — 100-200ms for micro-interactions. 200-300ms for page transitions. Nothing over 500ms.
3. **Ease-out for entering** — elements decelerate as they arrive (feels natural)
4. **Ease-in for exiting** — elements accelerate as they leave (gets out of the way)
5. **Reduced motion support** — ALWAYS respect `prefers-reduced-motion`

---

## Standard Durations

```css
--duration-fast: 100ms;    /* Hover, focus, color changes */
--duration-normal: 200ms;  /* Dropdowns, tooltips, modals appearing */
--duration-slow: 300ms;    /* Page transitions, large element moves */
```

## Standard Easings

```css
--ease-out: cubic-bezier(0, 0, 0.2, 1);      /* Elements entering */
--ease-in: cubic-bezier(0.4, 0, 1, 0.8);      /* Elements exiting */
--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1);  /* Moving between positions */
```

---

## Hover States

EVERY interactive element needs a hover response.

```tsx
// Button hover — subtle background shift
className="transition-colors duration-fast hover:bg-background-emphasis"

// Card hover — lift with shadow
className="transition-all duration-normal hover:shadow-md hover:-translate-y-0.5"

// Link hover — underline or color shift
className="transition-colors duration-fast hover:text-brand"

// Icon button — background appear
className="transition-colors duration-fast hover:bg-background-muted rounded-md p-2"
```

---

## Appear/Disappear

```tsx
// Dropdown appearing — scale + fade from anchor point
className="animate-in fade-in slide-in-from-top-2 duration-200"

// Modal overlay — fade in
className="animate-in fade-in duration-200"

// Modal content — scale up from center
className="animate-in fade-in zoom-in-95 duration-200"

// Toast — slide in from right
className="animate-in slide-in-from-right-full duration-300"
```

Tailwind `animate-in`/`animate-out` classes (from tailwindcss-animate plugin):
- `fade-in` / `fade-out`
- `zoom-in-95` / `zoom-out-95`
- `slide-in-from-top-2` / `slide-out-to-top-2`
- `spin-in` / `spin-out`

---

## Skeleton Shimmer

```css
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.skeleton-shimmer {
  background: linear-gradient(
    90deg,
    hsl(var(--background-muted)) 25%,
    hsl(var(--background-emphasis)) 50%,
    hsl(var(--background-muted)) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}
```

Or use Tailwind's built-in: `animate-pulse` (simpler, usually sufficient).

---

## Page Transitions

For Next.js App Router, use `loading.tsx` files:

```tsx
// app/dashboard/loading.tsx
export default function Loading() {
  return <DashboardSkeleton />;
}
```

For animated transitions between routes, use `framer-motion` or View Transitions API:
```tsx
// Fade between pages
<motion.div
  initial={{ opacity: 0, y: 8 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.2, ease: [0, 0, 0.2, 1] }}
>
  {children}
</motion.div>
```

---

## Scroll Animations

Use Intersection Observer for scroll-triggered animations:

```tsx
// Fade in on scroll — use sparingly, only for marketing pages
function FadeInOnScroll({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useIntersectionObserver(ref, { threshold: 0.1 });

  return (
    <div
      ref={ref}
      className={cn(
        "transition-all duration-slow",
        isInView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
      )}
    >
      {children}
    </div>
  );
}
```

NEVER use scroll animations in dashboard/admin interfaces. They belong on marketing pages only.

---

## Stagger Effects

Items entering in sequence, with a slight delay between each:

```tsx
// Stagger list items
{items.map((item, i) => (
  <div
    key={item.id}
    className="animate-in fade-in slide-in-from-bottom-2"
    style={{ animationDelay: `${i * 50}ms`, animationFillMode: "backwards" }}
  >
    <ItemCard {...item} />
  </div>
))}
```

Max delay: 500ms total (10 items x 50ms). Beyond that, stagger feels slow.

---

## Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
  }
}
```

Already in the globals-template.css. NEVER skip this.

---

## Anti-patterns

- Bounce/spring easing in professional interfaces (too playful)
- Animations longer than 500ms (feels slow)
- Animating layout properties (width, height) — animate transform instead
- Scroll hijacking (overriding native scroll behavior)
- Auto-playing videos or animations without user control
- Animation on EVERY element (sensory overload)
