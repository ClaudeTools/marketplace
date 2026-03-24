---
title: "Design a UI"
description: "Build production-grade interfaces with a consistent design system, responsive screenshots, and automated contrast auditing."
---

**Difficulty: Intermediate**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- A frontend project (React, Next.js, Vite, Astro, or SvelteKit) or a blank directory
- [Set Up a New Project](setup-new-project.md) — codebase index must be built before design system generation
:::

Use the frontend-design skill to build landing pages, dashboards, and components — with design direction established before any code is written, and a visual quality loop built in.

## Real scenarios

### Scenario A: Building a landing page from scratch

> "build a landing page for a legal document review SaaS — I want it to feel authoritative but approachable, not like a bank"

:::note[Behind the scenes]
The skill checks for `.frontend-design/system.md`. If it doesn't exist, it enters **Build Mode** and runs the intent-first workflow before touching any code.
:::

**Step 1 — Intent questions**

Claude responds with targeted questions rather than starting to code:

```
Before I start building, I need to understand a few things:

1. Who is the primary user — solo lawyers, law firm associates, legal ops teams, or non-lawyers reviewing contracts?
2. What's the single most important action on this page — start a free trial, book a demo, or upload a document?
3. Any examples of visual direction you like? (industries, not necessarily legal)
```

> "Legal ops teams at mid-size companies. Book a demo is the CTA. I like the feel of Linear — precise, confident, not sales-y."

**Step 2 — Domain exploration**

```
Domain exploration: legal document review

Vocabulary: redlines, clause library, playbook, escalation path, outside counsel, matter
Natural colors: aged parchment (#F5F0E8), deep mahogany (#3D1F0E), gold seal (#C9A84C),
               carbon black (#1A1A1A), document cream (#FAFAF7)
Signature element: a document "redline" visual — a subtle red strikethrough annotation
                   that appears in backgrounds/dividers, unique to this domain
Defaults I will NOT use: navy blue + white (screams law firm website),
                         stock photo of a handshake, the word "seamless"
```

**Step 3 — Design brief presented for approval**

```
Proposed direction: "Precision Document"

Palette: Carbon black primary, document cream backgrounds, gold as the single accent,
         a single muted red for the signature element
Typography: IBM Plex Sans (legal precision without the stuffiness),
            IBM Plex Mono for code/clause snippets
Spacing: 8px base, generous whitespace — documents breathe
Tone: Confident and specific, like a well-argued brief — not warm, not cold

CTA treatment: Single "Book a demo" button, gold on black, above the fold

Confirm this direction? (or tell me what to change)
```

> "yes go ahead"

:::note[Behind the scenes]
`generate-design-brief.sh` writes `.frontend-design/system.md` immediately. This protects the design decisions against context compaction in long sessions — any future agent reads this file before writing UI code.
:::

**Step 4 — Design tokens generated**

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py \
  --theme precision \
  --brand "#C9A84C"
```

This produces `globals.css` with semantic CSS custom properties:

```css
:root {
  --bg-background: #FAFAF7;
  --bg-surface: #F5F0E8;
  --text-foreground: #1A1A1A;
  --text-muted: #5C5C5C;
  --accent-primary: #C9A84C;
  --accent-signature: #B33A3A;
  /* ... */
}
```

All components reference these tokens. No raw Tailwind color classes like `bg-white` or `text-gray-800`.

**Step 5 — Components built against the brief**

Claude builds the landing page sections. Each component handles all data states and stays under 200 lines.

**Step 6 — Screenshot loop at 4 breakpoints**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/responsive-screenshots.sh http://localhost:3000
```

Screenshots captured at 375px, 768px, 1280px, and 1440px. Claude evaluates them against the brief before showing you anything.

**Step 7 — Audit catches a contrast issue**

```
Audit finding: text-muted (#5C5C5C) on bg-surface (#F5F0E8) = 3.8:1 contrast ratio
Required: 4.5:1 for WCAG AA (normal text)
Fix: darken --text-muted to #4A4A4A → contrast becomes 5.2:1
```

Claude applies the fix, re-runs the screenshot, and confirms the issue is resolved before presenting the result.

---

### Scenario B: Maintaining an existing design

> "add a pricing table to the landing page"

:::note[Behind the scenes]
The skill detects `.frontend-design/system.md` and enters **Maintain Mode**. No new design direction is proposed — the existing tokens and patterns are followed exactly.
:::

```
Loading design system from .frontend-design/system.md...

Existing tokens: --accent-primary: #C9A84C, --bg-surface: #F5F0E8, ...
Pattern: cards use 24px padding, 1px border with --border-subtle, no box-shadows

Building pricing table following existing patterns...
```

---

:::tip[When to intervene in the design process]
- **If Claude defaults to blue + gray**: Push back before it writes any code — ask for the domain exploration outputs first
- **If a proposed brief feels generic**: Ask "what are the three defaults you're actively avoiding?" — this forces specificity
- **If you want to change direction mid-build**: Say "start over on the design brief" — it re-runs intent questions without losing code already written
- **For existing projects**: Say "extract the design system from this project" before anything else — this prevents conflicting token sets
:::

## What happens behind the scenes

- **design-system.py** generates a complete CSS custom property system from a color seed and spacing ratio
- **validate-design.sh** catches raw color values, missing tokens, and oversized components structurally
- **audit-design.py** runs a contrast matrix, spacing grid check, and vertical rhythm audit — WCAG AA compliance is the minimum
- **responsive-screenshots.sh** uses headless Chrome at 375px, 768px, 1280px, 1440px, handling sticky navs correctly
- **system.md** is the single source of truth for design decisions — all agents in a multi-agent session read it before writing UI code

## Tips

- In a multi-agent session, write `system.md` before spawning implementation teammates — they all start from the same design foundation
- The contrast audit is non-negotiable — if Claude tries to skip it, ask explicitly: "run the contrast audit before finishing"
- For a project with an existing design, always extract the system first: "extract the design system from this project"

## Related

- [Build a Feature](build-a-feature.md) — feature-pipeline can spawn frontend-design for UI features
- [Set Up a New Project](setup-new-project.md) — scaffold a project with the right stack before designing
- [Coordinate Agents](coordinate-agents.md) — share `system.md` decisions across a multi-agent UI build
