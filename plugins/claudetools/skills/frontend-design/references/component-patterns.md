# Component Patterns

Specific implementation patterns with code examples. These patterns show implementation with shadcn/ui. For other component libraries, apply the same structural patterns using equivalent components.

---

## Framework-Agnostic Principles

These apply regardless of component library:

- **Navigation context is always required.** Sidebar, breadcrumbs, or location indicators — a floating table is a component demo, not a product.
- **Metric displays have infinite expressions.** Not always icon-left-number-big-label-small. Hero number, inline stat, sparkline, gauge, progress bar, comparison delta, trend badge.
- **Every interactive element needs hover, focus, active, and disabled states.** No exceptions.
- **Images: always real, never placeholder boxes.** Use Unsplash URLs or ask the user to provide assets.

---

## Form Layouts (shadcn/ui: FieldGroup + Field)

Use `FieldGroup` + `Field` + `FieldLabel`. NOT raw divs with `space-y-*`.

```tsx
<FieldGroup>
  <Field>
    <FieldLabel htmlFor="name">Full Name</FieldLabel>
    <Input id="name" placeholder="Jane Doe" />
  </Field>
  <Field>
    <FieldLabel htmlFor="email">Email Address</FieldLabel>
    <Input id="email" type="email" placeholder="jane@example.com" />
  </Field>
  <Field>
    <FieldLabel htmlFor="message">Message</FieldLabel>
    <Textarea id="message" placeholder="How can we help?" rows={4} />
  </Field>
</FieldGroup>
```

## Form Grouping (shadcn/ui: FieldSet + FieldLegend)

Use `FieldSet` + `FieldLegend` for related checkboxes, radios, or switches.

```tsx
<FieldSet>
  <FieldLegend>Notification Channels</FieldLegend>
  <div className="flex flex-col gap-3">
    <div className="flex items-center gap-2">
      <Checkbox id="email-notif" />
      <Label htmlFor="email-notif">Email notifications</Label>
    </div>
    <div className="flex items-center gap-2">
      <Checkbox id="sms-notif" />
      <Label htmlFor="sms-notif">SMS notifications</Label>
    </div>
  </div>
</FieldSet>
```

## Inputs (shadcn/ui: InputGroup)

Use `InputGroup` with `InputGroupInput` (not raw `Input`) for decorated inputs.

```tsx
// Search input with icon
<InputGroup>
  <InputGroupAddon><Search className="h-4 w-4" /></InputGroupAddon>
  <InputGroupInput placeholder="Search products..." />
</InputGroup>

// Currency input with prefix and suffix
<InputGroup>
  <InputGroupAddon><DollarSign className="h-4 w-4" /></InputGroupAddon>
  <InputGroupInput type="number" placeholder="0.00" />
  <InputGroupAddon>USD</InputGroupAddon>
</InputGroup>
```

## Empty States (shadcn/ui: Empty)

Use `Empty` component, not custom markup.

```tsx
<Empty icon={<Inbox className="h-10 w-10" />} title="No messages yet"
  description="Start a conversation to see messages here.">
  <Button>New Message</Button>
</Empty>
```

## Loading States (shadcn/ui: Spinner)

Use `Spinner` for buttons. Never raw loading text.

```tsx
<Button disabled={isPending}>
  {isPending && <Spinner className="mr-2 h-4 w-4" />}
  {isPending ? "Saving..." : "Save Changes"}
</Button>
```

## Button Groups (shadcn/ui: ButtonGroup)

`ButtonGroup` for actions. `ToggleGroup` for state toggles.

```tsx
// Action buttons
<ButtonGroup>
  <Button variant="outline">Cancel</Button>
  <Button>Save</Button>
</ButtonGroup>

// State toggle
<ToggleGroup type="single" defaultValue="grid">
  <ToggleGroupItem value="grid" aria-label="Grid view">Grid</ToggleGroupItem>
  <ToggleGroupItem value="list" aria-label="List view">List</ToggleGroupItem>
</ToggleGroup>
```

## Charts (shadcn/ui: ChartContainer + Recharts)

Recharts with shadcn `ChartTooltip` for consistent styling. For other stacks, use the project's charting library.

```tsx
"use client";
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import { ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart";

const chartConfig = { revenue: { label: "Revenue", color: "hsl(var(--primary))" } };

export function RevenueChart({ data }: { data: { month: string; revenue: number }[] }) {
  return (
    <ChartContainer config={chartConfig} className="h-[300px] w-full">
      <AreaChart data={data}>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
        <XAxis dataKey="month" className="text-muted-foreground" />
        <YAxis className="text-muted-foreground" />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Area type="monotone" dataKey="revenue" fill="hsl(var(--primary))"
          fillOpacity={0.1} stroke="hsl(var(--primary))" strokeWidth={2} />
      </AreaChart>
    </ChartContainer>
  );
}
```

## Navigation Context (Any Framework)

Screens need grounding. A floating table is a component demo, not a product. Include:
- **Sidebar or top nav** showing location in the app
- **Location indicators** — breadcrumbs, page title, active nav state
- **User context** — who is logged in, workspace/org

```tsx
export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen">
      <aside className="w-64 border-r border-border bg-background">
        <nav className="flex flex-col gap-1 p-4">
          <NavItem href="/dashboard" icon={<LayoutDashboard />} active>Dashboard</NavItem>
          <NavItem href="/orders" icon={<ShoppingCart />}>Orders</NavItem>
          <NavItem href="/settings" icon={<Settings />}>Settings</NavItem>
        </nav>
        <div className="mt-auto border-t border-border p-4"><UserMenu /></div>
      </aside>
      <main className="flex-1 overflow-y-auto p-6">{children}</main>
    </div>
  );
}
```

Sidebar uses same `bg-background` as main content with `border-r` for separation.

## Metric Display (Any Framework)

NOT always icon-left-number-big-label-small. Options: hero number, inline stat, sparkline, gauge, progress bar, comparison delta, trend badge. Each metric should feel unique.

```tsx
// Hero metric — large, prominent
<div className="flex flex-col gap-1">
  <span className="text-sm text-muted-foreground">Monthly Revenue</span>
  <span className="text-4xl font-semibold tracking-tight text-foreground">$48,290</span>
  <span className="text-sm text-emerald-600">+12.5% from last month</span>
</div>

// Inline stat — compact
<div className="flex items-baseline gap-2">
  <span className="font-mono text-lg tabular-nums text-foreground">2,847</span>
  <span className="text-xs text-muted-foreground">active users</span>
</div>
```

## Image Handling

- ALWAYS prefer real images. NEVER placeholder gray boxes
- NEVER abstract shapes/blobs as filler
- Use descriptive `alt` text for all images
- Set `crossOrigin="anonymous"` for images on `<canvas>`
