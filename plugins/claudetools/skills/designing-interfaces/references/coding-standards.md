# Coding Standards

Universal and framework-specific standards for the frontend design skill.

---

## Universal Standards

These apply to ALL stacks.

### Component Architecture

- Split code into multiple components. No monolithic page files.
- Import components from separate files.
- Wrap titles in `text-balance` or `text-pretty`.
- Escape JSX special chars: `{'1 + 1 < 3'}` not `1 + 1 < 3`.

### Data Fetching

Use framework-appropriate patterns. NEVER fetch inside `useEffect`.

- **Next.js:** SWR for client-side, RSC for server data
- **React + Vite:** TanStack Query or SWR
- **SvelteKit:** `load` functions
- **Astro:** fetch in frontmatter or component scripts

### Data Persistence

ALWAYS use a real database integration, NEVER localStorage or client-side-only storage (unless explicitly requested).

- If using Supabase: use native Supabase Auth (not custom auth)
- If using another provider (Neon, Prisma, Drizzle, etc.): build custom auth with bcrypt, secure sessions, database-backed users
- ALWAYS determine the database provider early — before writing data layer code

### Security

- bcrypt password hashing for custom auth
- HTTP-only cookies for session management
- RLS with Supabase, parameterized queries everywhere
- ALWAYS validate and sanitize all inputs

### Accessibility

- Use semantic HTML (`main`, `header`, `nav`, `section`) with correct ARIA roles
- Use `sr-only` class for screen-reader-only text
- Add alt text for all non-decorative images

### Image and Media Handling

- When a user provides an image, save it to `public/images/` and reference via local path (`/images/logo.png`)
- NEVER leave blob URLs in application code — download to filesystem first
- Supported media: `glb`, `gltf` for 3D models, `mp3` with native `<audio>` element
- ALWAYS prefer real images over placeholders

### Debugging

Use labeled console.log statements to trace execution flow. Remove when resolved.

```tsx
console.log("[debug] User data received:", userData);
console.log("[debug] API call with params:", params);
```

### Canvas Images

Set `crossOrigin="anonymous"` on `new Image()` when rendering images to `<canvas>` to avoid CORS issues.

### Common Mistakes

```tsx
// WRONG: fetching in useEffect
useEffect(() => { fetch("/api/data").then(r => r.json()).then(setData) }, []);

// CORRECT: use framework data fetching (SWR, TanStack Query, RSC, load functions)
const { data } = useSWR("/api/data", fetcher);

// WRONG: localStorage for persistence
localStorage.setItem("user", JSON.stringify(user));

// CORRECT: database via API route
await fetch("/api/users", { method: "POST", body: JSON.stringify(user) });

// WRONG: raw color classes
<div className="bg-white text-gray-800 border-gray-200">

// CORRECT: semantic tokens
<div className="bg-background text-foreground border-border">
```

### Visual Elements

- ALWAYS prefer real images. NEVER placeholder gray boxes or abstract blobs
- NEVER create SVGs for complex illustrations. Use libraries for maps
- NEVER use emojis as icons. Consistent icon sizing: 16px, 20px, 24px

---

## Next.js

**When the project uses Next.js.**

### Next.js 16

App Router is the default. Key changes:

- **Turbopack** is the default bundler (stable)
- **React Compiler** support is stable (`reactCompiler: true` in next.config.js)
- `params`, `searchParams`, `headers`, `cookies` MUST be awaited in Server Components
- `middleware.ts` is now `proxy.js` (backwards compatible)
- Update layout.tsx metadata (title, description) and viewport (theme-color) for SEO

### Cache Components

```tsx
// next.config.ts — enable cache components
const nextConfig = { cacheComponents: true };

// Page-level: add "use cache" at top of file
"use cache";
export default async function Page() {
  const data = await fetch("/api/products");
  return <ProductList data={data} />;
}

// Component-level
export async function PricingTable() {
  "use cache";
  return <Table data={await getPlans()} />;
}
```

### Caching APIs

```ts
revalidateTag("blog-posts", "max"); // Built-in profiles: 'max', 'days', 'hours'
revalidateTag("products", { revalidate: 3600 }); // Custom time
updateTag(`user-${userId}`); // Server Actions only — read-your-writes
refresh(); // Server Actions only — refresh uncached data
```

### React 19.2

```tsx
// useEffectEvent — non-reactive logic extracted from Effects
import { useEffectEvent } from "react";
function ChatRoom({ roomId, theme }: { roomId: string; theme: string }) {
  const onConnected = useEffectEvent(() => showNotification("Connected!", theme));
  useEffect(() => {
    const conn = createChatConnection(roomId);
    conn.on("connected", () => onConnected());
    return () => conn.disconnect();
  }, [roomId]); // theme NOT in deps
}

// Activity — hide/show UI preserving state
import { Activity } from "react";
<Activity mode={showSidebar ? "visible" : "hidden"}><Sidebar /></Activity>
```

### Fonts (Next.js)

```tsx
// layout.tsx — font setup with CSS variables
import { Geist, Geist_Mono } from "next/font/google";
const geistSans = Geist({ subsets: ["latin"], variable: "--font-geist-sans" });
const geistMono = Geist_Mono({ subsets: ["latin"], variable: "--font-geist-mono" });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
```

### SWR (Client-Side Data)

```tsx
"use client";
import useSWR from "swr";
const fetcher = (url: string) => fetch(url).then((r) => r.json());

export function UserDashboard({ userId }: { userId: string }) {
  const { data, error, isLoading } = useSWR(`/api/users/${userId}`, fetcher, {
    refreshInterval: 30000,
  });
  if (isLoading) return <Spinner />;
  if (error) return <Empty title="Failed to load" description={error.message} />;
  return (
    <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
      {data.metrics.map((m: Metric) => <MetricCard key={m.id} {...m} />)}
    </div>
  );
}
```

### Starter Template Files

These files ALREADY EXIST in a standard Next.js + shadcn project. NEVER regenerate unless explicitly requested:

- `app/layout.tsx`, `app/globals.css`, `next.config.mjs`, `package.json`, `tsconfig.json`, `tailwind.config.ts`
- `components/ui/*`, `hooks/use-mobile.tsx`, `hooks/use-toast.ts`, `lib/utils.ts`

ALWAYS read these files before editing them.

---

## React + Vite

**When the project uses Vite with React.**

- Configure via `vite.config.ts` with `@vitejs/plugin-react`
- Routing: React Router or TanStack Router
- Data fetching: TanStack Query or SWR (no RSC available)
- Font loading: `@fontsource` packages or CSS `@import`
- Tailwind config in `tailwind.config.ts` or `postcss.config.js`

---

## shadcn/ui

**When the project uses shadcn/ui components.**

### New Components

| Component | Purpose |
|---|---|
| `ButtonGroup` | Grouped action buttons |
| `Empty` | Empty states |
| `Field` / `FieldGroup` / `FieldLabel` | Form layouts |
| `FieldSet` / `FieldLegend` | Checkbox/radio/switch groups |
| `InputGroup` / `InputGroupInput` / `InputGroupAddon` | Decorated inputs |
| `Kbd` | Keyboard shortcuts |
| `Spinner` | Loading buttons |

### Form Example

```tsx
<FieldGroup>
  <Field>
    <FieldLabel htmlFor="email">Email</FieldLabel>
    <InputGroup>
      <InputGroupAddon>@</InputGroupAddon>
      <InputGroupInput id="email" type="email" placeholder="you@example.com" />
    </InputGroup>
  </Field>
  <Button disabled={isPending}>
    {isPending && <Spinner className="mr-2" />}
    Submit
  </Button>
</FieldGroup>
```

---

## AI Integration

**When building AI features.**

AI SDK by Vercel: `ai@^6.0.0`, `@ai-sdk/react@^3.0.0`. Uses AI Gateway by default — no provider packages needed, pass a model string to `model` parameter.

**Zero-config providers:** AWS Bedrock, Google Vertex, OpenAI, Fireworks AI, Anthropic. Models: `"openai/gpt-5-mini"`, `"anthropic/claude-opus-4.6"`, `"google/gemini-3-flash"`.

**Requires API key:** xAI (Grok), Groq, Fal, DeepInfra — user must set `AI_GATEWAY_API_KEY`.

**Image/video generation:** AI Gateway supports generation models. `"google/gemini-3.1-flash-image-preview"` is a multi-modal LLM for interleaved text and images.

---

## SQL Scripts

**When working with databases.**

- Make sure tables exist before updating data
- Split SQL scripts into multiple files for better organization
- Do not rewrite or delete existing SQL scripts that have already been executed — only add new ones for modifications

---

## Package Manager

Use the project's existing package manager. For new projects, **pnpm** is recommended.

Tailwind config: apply via `font-sans`, `font-mono`, `font-serif` classes. Configure font families in `tailwind.config.ts`:

```ts
fontFamily: {
  sans: ["var(--font-geist-sans)"],
  mono: ["var(--font-geist-mono)"],
},
```
