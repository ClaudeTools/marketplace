---
title: "Design a UI"
description: "Design a UI — claudetools documentation."
---
Use the designing-interfaces skill to build production-grade frontend interfaces — landing pages, dashboards, web apps, or individual components — with a consistent design system and visual quality checks built in.


## What you need
- claudetools installed
- A Next.js, Vite, Astro, SvelteKit, or plain HTML/CSS project (or start from scratch)
- Chrome available for headless screenshots (optional but recommended)

## Steps

### 1. Describe what you want to build

```
build a dashboard for a SaaS invoicing app — sidebar nav, metrics at the top, invoice table below
```

or to work on an existing page:

```
improve the design of src/pages/dashboard.tsx
```

### 2. Mode detection — build vs maintain

Claude evaluates your project before starting:

**Build mode** applies when building something new or redesigning from scratch. It runs the full intent-first workflow: exploring the product's domain, proposing a design direction, and generating a design brief before writing any code.

**Maintain mode** applies when the project has an existing design system (a `.frontend-design/system.md` file). Consistency is the goal — new components follow existing patterns, tokens are reused, and no new design directions are introduced.

### 3. Build mode — establish design direction first

For new or unstyled projects, Claude works through intent before any code:

**Intent** — Claude asks (or infers from context):
- Who is the user and what must they accomplish?
- What should the interface feel like? Not "clean and modern" — specific: warm like a notebook, dense like a trading floor?

**Domain exploration** — Claude produces four outputs:
1. Domain concepts and vocabulary from the product's world
2. Colors that exist naturally in this domain
3. One signature element that could only exist for this product
4. Three obvious defaults it will NOT use

**Theme selection** — Claude selects a starting theme and presents 2–3 options for your approval:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/design-system.py --list-domains
```

**Design brief** — Generated and presented for your confirmation before any code is written:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/generate-design-brief.sh "<goal>" "<context>"
```

### 4. Generate the design system

Once the direction is confirmed, Claude generates globals.css with the full token set:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/design-system.py \
  --theme midnight \
  --brand "#0D4F4F"
```

This produces semantic CSS custom properties (`--bg-background`, `--text-foreground`, etc.). All components reference these tokens — never raw Tailwind color values like `bg-white` or `text-gray-800`.

The design system is saved to `.frontend-design/system.md` immediately after the brief is confirmed, protecting decisions against context compaction in long sessions.

### 5. Build components

With the design system in place, Claude builds the components. Each component is written against the token system, handles all data states (loading, empty, error, populated), and stays under 200 lines before being split.

### 6. Preview loop — screenshot and evaluate

After writing UI code, Claude:

1. Starts the dev server if not running (`pnpm dev`)
2. Takes responsive screenshots at 4 breakpoints via headless Chrome:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/responsive-screenshots.sh http://localhost:3000
```

3. Evaluates the screenshots against the design brief
4. Fixes issues before presenting to you

You will not see half-finished work — the preview loop runs before every handoff.

### 7. Maintain mode — audit and fix existing design

For existing projects, run the audit workflow:

```
audit the design of this project
```

Claude runs:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/extract-system.py --dir .
bash ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/validate-design.sh .
python3 ${CLAUDE_PLUGIN_ROOT}/skills/designing-interfaces/scripts/audit-design.py --dir .
```

Findings are categorized as auto-fixable (hardcoded colors, wrong spacing classes) or manual (contrast failures, missing state handling). Claude offers to apply auto-fixable issues in a batch, then reports the score delta after re-running the audit.

## What happens behind the scenes

- **design-system.py** generates a complete CSS custom property system from a color seed and spacing ratio
- **validate-design.sh** catches raw color values, missing tokens, and oversized components structurally
- **audit-design.py** runs a contrast matrix, spacing grid check, and vertical rhythm audit
- **responsive-screenshots.sh** uses headless Chrome to capture full-page screenshots at 375px, 768px, 1280px, and 1440px, handling sticky navs correctly
- **system.md** is the single source of truth for design decisions — all agents in a multi-agent session read it before writing UI code

## Tips

- If Claude defaults to blue + gray with a sidebar + card grid layout, push back — ask for the domain exploration outputs before it touches code
- For a project with an existing design, always extract the system first: "extract the design system from this project"
- The contrast audit is non-negotiable — WCAG AA compliance is the minimum
- In a multi-agent session, write system.md before spawning implementation teammates so they all start from the same design foundation

## Related

- [Build a Feature](build-a-feature.md) — feature-pipeline can spawn designing-interfaces for UI features
- [Set Up a New Project](setup-new-project.md) — scaffold a project with the right stack
- [Reference: designing-interfaces skill](../reference/skills.md)
