# UI State Patterns

Every data-dependent component has 5 states. Missing ANY of them makes the interface feel broken.

---

## The 5 States

| State | When | Pattern |
|-------|------|---------|
| **Loading** | Data is being fetched | Skeleton screen or spinner |
| **Empty** | No data exists yet | Helpful message + CTA |
| **Error** | Fetch or operation failed | Error message + retry |
| **Partial** | Some data loaded, more coming | Progressive loading |
| **Populated** | Data is available | The "normal" view |

ALWAYS implement all 5. Design the empty and error states with the same care as the populated state.

---

## Skeleton Screens

Skeletons show the SHAPE of content before it loads. Better than spinners — they set expectations about what's coming.

```tsx
// Skeleton component — animate with pulse
function Skeleton({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "animate-pulse rounded-md bg-background-muted",
        className
      )}
    />
  );
}

// Usage: match the exact layout of your populated state
function DashboardSkeleton() {
  return (
    <div className="grid gap-4 md:grid-cols-3">
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="rounded-lg border p-6">
          <Skeleton className="h-4 w-24 mb-2" />  {/* Label */}
          <Skeleton className="h-8 w-16 mb-4" />  {/* Number */}
          <Skeleton className="h-2 w-full" />      {/* Sparkline */}
        </div>
      ))}
    </div>
  );
}
```

**Rules:**
- Match skeleton shape to actual content layout
- Use `animate-pulse` (Tailwind built-in) — not shimmer (too flashy)
- Gray background slightly darker than surface (use `bg-background-muted`)
- Show for minimum 300ms to avoid flash (even if data loads faster)

---

## Empty States

Empty states are OPPORTUNITIES, not dead ends. They teach users what to do.

```tsx
function EmptyProjects() {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <div className="rounded-full bg-background-subtle p-4 mb-4">
        <FolderIcon className="h-8 w-8 text-foreground-muted" />
      </div>
      <h3 className="text-lg font-semibold mb-1">No projects yet</h3>
      <p className="text-foreground-secondary mb-4 max-w-sm">
        Create your first project to start tracking your work.
      </p>
      <Button>
        <PlusIcon className="h-4 w-4 mr-2" />
        Create Project
      </Button>
    </div>
  );
}
```

**Rules:**
- Icon or illustration (not just text)
- Clear explanation of why it's empty
- Primary action to resolve the empty state
- Use `text-center` and generous `py-16` — empty states need breathing room

---

## Error States

```tsx
function ErrorState({ error, retry }: { error: Error; retry: () => void }) {
  return (
    <div className="rounded-lg border border-destructive/20 bg-destructive/5 p-6">
      <div className="flex items-start gap-3">
        <AlertCircle className="h-5 w-5 text-destructive mt-0.5" />
        <div>
          <h3 className="font-semibold text-destructive">Something went wrong</h3>
          <p className="text-sm text-foreground-secondary mt-1">
            {error.message || "We couldn't load this content. Please try again."}
          </p>
          <Button variant="outline" size="sm" onClick={retry} className="mt-3">
            Try again
          </Button>
        </div>
      </div>
    </div>
  );
}
```

**Types of errors:**
- **Inline**: Replace the component that failed (not the whole page)
- **Toast**: Transient errors (network timeout, save failed)
- **Full page**: Critical failures (auth expired, 500 error)
- **Field-level**: Form validation errors (next to the input)

---

## Loading Indicators

| Context | Pattern | Duration |
|---------|---------|----------|
| Page load | Skeleton screen | > 300ms |
| Button action | Spinner inside button | Any |
| Form submit | Button disabled + spinner | Any |
| Background save | Subtle toast or status dot | < 2s |
| Long operation | Progress bar with percentage | > 5s |

```tsx
// Button with loading state
<Button disabled={isPending}>
  {isPending && <Spinner className="h-4 w-4 mr-2" />}
  {isPending ? "Saving..." : "Save changes"}
</Button>
```

---

## Optimistic Updates

For fast-feeling interactions, update the UI BEFORE the server responds:

```tsx
// Show the new item immediately, revert on error
const addItem = async (item: Item) => {
  const optimisticId = crypto.randomUUID();
  setItems(prev => [...prev, { ...item, id: optimisticId, _pending: true }]);

  try {
    const saved = await api.createItem(item);
    setItems(prev => prev.map(i => i.id === optimisticId ? saved : i));
  } catch {
    setItems(prev => prev.filter(i => i.id !== optimisticId));
    toast.error("Failed to add item");
  }
};
```

---

## Transitions Between States

Don't jump between states — transition smoothly:
- Loading -> Populated: fade skeleton out, fade content in (`animate-in fade-in`)
- Populated -> Loading (refetch): dim content + overlay spinner, DON'T replace with skeleton
- Any -> Error: slide error in from top or fade in place
