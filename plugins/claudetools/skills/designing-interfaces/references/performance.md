# Frontend Performance

Performance is a design decision. A beautiful interface that loads in 5 seconds is a bad interface.

---

## Core Web Vitals Targets

| Metric | Target | What it measures |
|--------|--------|------------------|
| LCP (Largest Contentful Paint) | < 2.5s | Largest visible element render time |
| INP (Interaction to Next Paint) | < 200ms | Response time to user interactions |
| CLS (Cumulative Layout Shift) | < 0.1 | Visual stability (things not jumping around) |

---

## Image Optimization

Images are the #1 performance bottleneck.

```tsx
// ALWAYS use next/image for automatic optimization
import Image from "next/image";

<Image
  src="/images/hero.jpg"
  alt="Product hero image"
  width={1200}
  height={630}
  priority        // Above-the-fold images: load immediately
  placeholder="blur"
  blurDataURL="..." // Low-quality placeholder
/>
```

**Rules:**
- ALWAYS specify `width` and `height` (prevents CLS)
- Use `priority` for above-the-fold images (hero, logo)
- Use `loading="lazy"` for below-the-fold (default in next/image)
- Serve WebP/AVIF formats (next/image does this automatically)
- Size images to their display size (don't serve 4000px for a 400px card)

### For non-Next.js projects:
```html
<img
  src="/images/hero.webp"
  alt="Hero"
  width="1200"
  height="630"
  loading="lazy"
  decoding="async"
/>
```

---

## Font Loading

Fonts cause layout shift when they swap in. Minimize this:

```tsx
// Next.js: use next/font (preloads, no layout shift)
import { Inter } from "next/font/google";
const inter = Inter({ subsets: ["latin"], display: "swap" });
```

**Rules:**
- `display: "swap"` — show text immediately in fallback font, swap when loaded
- Limit to 2 font families (each adds ~20-50KB)
- Use `variable` fonts when available (one file covers all weights)
- Preload the critical font: `<link rel="preload" href="/fonts/Inter.woff2" as="font" crossOrigin="anonymous" />`

---

## Code Splitting

Don't load everything upfront.

```tsx
// Lazy load heavy components
import dynamic from "next/dynamic";

const Chart = dynamic(() => import("@/components/chart"), {
  loading: () => <Skeleton className="h-64" />,
  ssr: false, // Client-only components
});

// Lazy load below-the-fold sections
const Features = dynamic(() => import("@/components/features"));
```

---

## Bundle Size

```bash
# Analyze bundle size
npx next build && npx @next/bundle-analyzer
```

**Rules:**
- Import specific modules, not entire libraries: `import { format } from "date-fns"` not `import * as dateFns`
- Use tree-shakeable libraries
- Avoid importing large dependencies in Server Components that only need to run on the client
- Check bundle with `npx next build` — aim for < 100KB First Load JS per route

---

## Layout Shift Prevention

CLS is the most common performance failure:

- ALWAYS set `width`/`height` on images and videos
- ALWAYS reserve space for dynamic content with `min-height`
- NEVER inject content above existing content after load
- Use skeleton screens (they reserve the correct space)
- Set explicit dimensions on ad slots, embeds, iframes

```tsx
// Reserve space for an image that hasn't loaded
<div className="aspect-video bg-background-muted rounded-lg overflow-hidden">
  <Image src={src} alt={alt} fill className="object-cover" />
</div>
```

---

## Preloading and Prefetching

```tsx
// Preload critical resources
<link rel="preload" href="/api/user" as="fetch" crossOrigin="anonymous" />

// Prefetch likely next pages (Next.js does this for <Link> automatically)
<Link href="/dashboard" prefetch>Dashboard</Link>

// DNS prefetch for third-party domains
<link rel="dns-prefetch" href="https://fonts.googleapis.com" />
```

---

## Performance Checklist

Before shipping, verify:
- [ ] Images: next/image or lazy loading, proper dimensions, WebP format
- [ ] Fonts: 2 families max, preloaded, display:swap
- [ ] Bundle: < 100KB First Load JS per route
- [ ] LCP: < 2.5s (check with Lighthouse)
- [ ] CLS: < 0.1 (no layout shifts)
- [ ] INP: < 200ms (interactions feel instant)
- [ ] No render-blocking resources
- [ ] Dynamic imports for heavy/below-fold components
