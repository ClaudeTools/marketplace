# Accessibility

Requirements for WCAG compliance, semantic HTML, and inclusive design.

---

## Semantic HTML

Use landmark elements, not div soup: `main`, `header`, `nav`, `section`, `article`, `aside`, `footer`.

```tsx
export function AppPage() {
  return (
    <>
      <header className="border-b border-border">
        <nav aria-label="Main navigation">
          <a href="/dashboard">Dashboard</a>
          <a href="/settings">Settings</a>
        </nav>
      </header>
      <main className="flex-1">
        <section aria-labelledby="overview-heading">
          <h2 id="overview-heading">Overview</h2>
        </section>
      </main>
    </>
  );
}
```

## ARIA

- `aria-label` for icon buttons and unlabeled interactive elements
- `aria-describedby` to link form inputs with error/help text
- `aria-hidden="true"` for decorative elements (icons next to text)
- `aria-expanded` for collapsible sections and dropdowns
- `aria-live="polite"` for dynamic content updates
- `role="status"` for loading indicators
- `sr-only` Tailwind class for screen-reader-only content

```tsx
<button aria-label="Close dialog" className="rounded-md p-2 hover:bg-accent">
  <X className="h-4 w-4" />
  <span className="sr-only">Close dialog</span>
</button>
```

## Touch Targets

44px minimum for ALL interactive elements. Applies to buttons, links, form controls.

```tsx
<button className="flex h-11 min-w-[44px] items-center justify-center rounded-md px-4">
  Submit
</button>
<button className="flex h-11 w-11 items-center justify-center rounded-md">
  <Menu className="h-5 w-5" />
</button>
```

## Font Sizing

- **16px minimum** for text inputs (prevents iOS Safari auto-zoom on focus)
- **14px minimum** for body text. Use `rem` units via Tailwind classes

## Mobile Viewport

```tsx
export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#ffffff",
};
```

Set `background-color` on `html` for Safari overscroll: `html { background-color: hsl(var(--background)); }`

## Color Contrast

WCAG AA: 4.5:1 for normal text, 3:1 for large text (18px+ or 14px bold), 3:1 for UI components.

- Semantic colors need accessible contrast against their backgrounds
- Never rely on color alone — pair with icons or text
- Test both light and dark mode

## Focus Management

Visible focus rings on all interactive elements. Logical tab order.

```tsx
<button className="rounded-md px-4 py-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2">
  Action
</button>
```

### Modal Focus Trap

Use native `<dialog>` for automatic focus trapping and Escape key handling.

```tsx
"use client";
import { useEffect, useRef } from "react";

export function Modal({ open, onClose, children }: {
  open: boolean; onClose: () => void; children: React.ReactNode;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = dialogRef.current;
    if (!d) return;
    open ? d.showModal() : d.close();
  }, [open]);

  return (
    <dialog ref={dialogRef} onClose={onClose} aria-labelledby="modal-title"
      className="rounded-lg border border-border bg-background p-6 shadow-lg backdrop:bg-black/50">
      <div className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <h2 id="modal-title" className="text-lg font-semibold">Title</h2>
          <button onClick={onClose} aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-md hover:bg-accent">
            <X className="h-4 w-4" />
          </button>
        </div>
        {children}
      </div>
    </dialog>
  );
}
```

## Forms

Every input needs a visible label. Errors linked with `aria-describedby`.

```tsx
<Field>
  <FieldLabel htmlFor="username">
    Username <span className="text-destructive">*</span>
  </FieldLabel>
  <Input
    id="username" required aria-required="true"
    aria-invalid={!!errors.username}
    aria-describedby={errors.username ? "username-error" : undefined}
    className={errors.username ? "border-destructive" : ""}
  />
  {errors.username && (
    <p id="username-error" role="alert" className="text-sm text-destructive">
      {errors.username}
    </p>
  )}
</Field>
```

Requirements: visible labels via `FieldLabel`, required indicators with `aria-required`, errors via `aria-describedby` + `role="alert"`, invalid state via `aria-invalid`, success with `aria-live="polite"`.

## Responsive Navigation

```tsx
"use client";
import { useState } from "react";

export function ResponsiveNav() {
  const [isOpen, setIsOpen] = useState(false);
  return (
    <header className="border-b border-border">
      <div className="flex h-14 items-center justify-between px-4">
        <a href="/" className="text-lg font-semibold">App</a>
        <button className="flex h-11 w-11 items-center justify-center rounded-md md:hidden"
          onClick={() => setIsOpen(!isOpen)} aria-expanded={isOpen}
          aria-controls="mobile-nav" aria-label={isOpen ? "Close menu" : "Open menu"}>
          {isOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
        <nav id="mobile-nav" className={`${isOpen ? "flex" : "hidden"} flex-col gap-1 md:flex md:flex-row`}>
          <a href="/dashboard" className="rounded-md px-3 py-2.5 text-sm hover:bg-accent">Dashboard</a>
          <a href="/settings" className="rounded-md px-3 py-2.5 text-sm hover:bg-accent">Settings</a>
        </nav>
      </div>
    </header>
  );
}
```

## PWA

- `manifest.json` matching site metadata with `name`, `short_name`, `theme_color`, `background_color`, `display`
- `themeColor` in viewport export. `manifest` path in metadata export.
