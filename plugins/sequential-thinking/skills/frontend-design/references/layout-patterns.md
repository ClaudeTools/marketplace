# Layout Patterns

Reusable layout architectures. Each pattern includes the structural HTML, Tailwind classes, and responsive behavior.

---

## Dashboard (Sidebar + Header + Content)

The most common admin/SaaS layout. Sidebar collapses to hamburger on mobile.

```tsx
<div className="flex h-dvh">
  {/* Sidebar — hidden on mobile */}
  <aside className="hidden lg:flex lg:w-64 flex-col border-r bg-background">
    <nav className="flex-1 p-4 space-y-1">
      {/* Nav items */}
    </nav>
  </aside>

  {/* Main area */}
  <div className="flex-1 flex flex-col min-w-0">
    {/* Header */}
    <header className="h-14 border-b flex items-center px-4 gap-4">
      <button className="lg:hidden">☰</button>
      <h1 className="text-lg font-semibold">Page Title</h1>
    </header>

    {/* Content */}
    <main className="flex-1 overflow-auto p-6">
      {children}
    </main>
  </div>
</div>
```

Key decisions: sidebar SAME background as content (not different color). `min-w-0` prevents flex overflow. `h-dvh` for mobile viewport.

---

## Marketing (Hero + Sections + Footer)

```tsx
<div className="min-h-dvh flex flex-col">
  <header className="h-16 border-b flex items-center px-4 sm:px-6 lg:px-8">
    {/* Nav */}
  </header>

  <main className="flex-1">
    {/* Hero — full width, contained content */}
    <section className="py-16 sm:py-24 lg:py-32">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        {/* Hero content */}
      </div>
    </section>

    {/* Features — grid */}
    <section className="py-16 bg-background-subtle">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
          {/* Feature cards */}
        </div>
      </div>
    </section>
  </main>

  <footer className="border-t py-8">
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      {/* Footer content */}
    </div>
  </footer>
</div>
```

Key: consistent container (`max-w-7xl mx-auto px-4 sm:px-6 lg:px-8`). Section spacing scales with viewport. Alternating bg colors for visual rhythm.

---

## Settings (Side Nav + Content Panel)

```tsx
<div className="mx-auto max-w-5xl px-4 py-8">
  <h1 className="text-2xl font-bold mb-8">Settings</h1>
  <div className="flex flex-col md:flex-row gap-8">
    {/* Side nav — stacks on mobile */}
    <nav className="md:w-48 flex-shrink-0">
      <ul className="flex md:flex-col gap-1">
        {/* Nav items */}
      </ul>
    </nav>

    {/* Content */}
    <div className="flex-1 min-w-0">
      {children}
    </div>
  </div>
</div>
```

---

## Auth (Centered Card)

```tsx
<div className="min-h-dvh flex items-center justify-center p-4 bg-background-subtle">
  <div className="w-full max-w-md">
    <div className="rounded-lg border bg-background p-6 sm:p-8 shadow-sm">
      {/* Form */}
    </div>
  </div>
</div>
```

---

## Split (50/50 or Golden Ratio)

```tsx
{/* Golden ratio: 38.2% / 61.8% */}
<div className="grid lg:grid-cols-[382fr_618fr] min-h-dvh">
  <div className="hidden lg:flex items-center justify-center bg-brand p-8">
    {/* Visual side */}
  </div>
  <div className="flex items-center justify-center p-4 sm:p-8">
    {/* Content side */}
  </div>
</div>
```

---

## Bento Grid (Mixed Sizes)

```tsx
<div className="grid gap-4 grid-cols-2 lg:grid-cols-4 auto-rows-[180px]">
  <div className="col-span-2 row-span-2 rounded-lg border p-6">
    {/* Large featured item */}
  </div>
  <div className="rounded-lg border p-4">{/* Small */}</div>
  <div className="rounded-lg border p-4">{/* Small */}</div>
  <div className="col-span-2 rounded-lg border p-4">{/* Wide */}</div>
</div>
```

Key: `auto-rows-[180px]` sets consistent row height. Large item spans 2x2 for focal point.

---

## Content Container Pattern

ALWAYS wrap page content in a consistent container:
```tsx
<div className="mx-auto w-full max-w-7xl px-4 sm:px-6 lg:px-8">
  {/* Content never exceeds 1280px, padding adapts to viewport */}
</div>
```

For reading content, use narrower measure:
```tsx
<article className="mx-auto max-w-prose">
  {/* 65ch width for optimal readability */}
</article>
```
