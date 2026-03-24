---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build a website, landing page, dashboard, web app, UI component, page layout, or any visual web interface. Also use when asked to redesign, restyle, make something look better, add dark mode, or create a design system. Covers React, Next.js, Vite, Astro, SvelteKit, Tailwind CSS, and plain HTML/CSS projects.
argument-hint: [description of what to build]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch, TaskCreate, TaskUpdate
metadata:
  author: Owen Innes
  version: 1.1.0
  category: frontend
  tags: [design, ui, frontend, tailwind, components, dashboard, landing-page, web-app]
---

# Designing Interfaces

Build distinctive, production-grade interfaces with craft and intent.

## Scope

**Use for:** Landing pages, dashboards, SaaS apps, marketing sites, web components, interactive pages, full-stack web applications, data visualizations, design systems, responsive layouts, dark mode implementation.

**Not for:** Pure backend services, CLI tools, mobile native apps, API-only projects, email templates. For applying Refactoring UI principles to existing code, use `/refactoring-ui` instead. For quick CSS fixes or single-property changes, just edit directly — this skill is for design-level work.

## Scripts

These scripts handle deterministic operations. Listed here so you know they exist before encountering workflow steps that reference them.

- `design-system.py` — Generate complete CSS design system from brand color + theme seed
- `color-system.py` — Color science: contrast check, palette generation, shade scale, color blindness sim, auto-fix
- `type-scale.py` — Modular scale, fluid typography, baseline grid snapping
- `audit-design.py` — Audit: contrast matrix, spacing grid, vertical rhythm, completeness score
- `validate-design.sh` — Structural checks: tokens, raw colors, font count, alt text, component size
- `extract-system.py` — Scan existing project → generate system.md draft
- `extract-design-from-image.py` — Structured prompts for screenshot analysis + reproduction checklist
- `responsive-screenshots.sh` — Headless Chrome screenshots at 4 breakpoints (full-page, handles sticky navs)
- `screenshot-compare.sh` — Pixel-diff comparison with RMSE scoring and region analysis
- `scaffold-project.sh` — Initialize Next.js/Vite/Astro project with design tokens
- `generate-design-brief.sh` — AI-generated design brief via Claude CLI
- `generate-tokens.sh` — CSS token generation from color inputs

All paths: `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/<name>`

---

## Mode Detection

Before starting work, determine which mode applies. Evaluate in order, stop at first match:

| Condition | Mode |
|-----------|------|
| User asks to audit, fix, maintain, update, or improve existing pages AND project has `.frontend-design/system.md` or an established design system | **Maintain Mode** |
| User asks to build new pages/features, redesign, or create from scratch | **Build Mode** |
| Project has no design system (new or unstyled) | **Build Mode** |

### Build Mode
Full creative workflow: intent exploration, domain exploration, theme selection, design brief, signature elements. Creative principles (swap test, signature test, sameness-is-failure) apply. Use when building something new where differentiation matters.

### Maintain Mode
Consistency IS the goal. Pages should look the same — that's the system working correctly. Do not apply swap test or signature test. Do not flag consistency as "defaulting." For a production app with an established design, matching existing patterns is the correct outcome.

In Maintain Mode, replace creative principles with:
- **Token consistency check** — all values reference system.md tokens
- **Pattern reuse check** — new components follow existing patterns
- **Regression check** — no existing functionality broken

---

## Audit Mode (Maintain Mode)

When the user asks to audit, fix design issues, or improve design consistency in an existing project:

### Step 1: Run Diagnostics
Run all three scripts in sequence:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-system.py --dir .
bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/validate-design.sh .
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/audit-design.py --dir .
```

### Step 2: Collate Results
Combine all outputs into a single prioritized report. Order by severity: FAIL > WARN > INFO.

### Step 3: Categorize Issues
Classify each issue as auto-fixable or manual:

**Auto-fixable** (safe to batch-fix):
- Hardcoded colors → replace with semantic tokens
- `space-*` classes → replace with `gap` classes
- Missing `alt` text → add descriptive alt attributes

**Manual** (requires design decisions):
- Contrast failures → needs color adjustment decisions
- Missing state handling → requires component logic
- Large components → requires architectural decisions
- Responsive issues → requires layout strategy

### Step 4: Present Report
Show the user: total issue count, breakdown by category, which are auto-fixable vs manual. Offer to auto-fix eligible issues.

### Step 5: Re-audit After Fixes
After applying fixes, re-run the audit scripts. The audit history in `.frontend-design/audit-history.json` shows the score delta — confirm improvement.

---

## Design-First Workflow (Build Mode)

Before writing any code, establish design direction.

### 1. Check for Existing Design

**Step A:** Look for `.frontend-design/system.md`. If it exists, read and apply it — decisions are already made. Skip to building.

**Step B:** If no system.md, check if the project already has a design:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-system.py --dir .
```
If existing tokens, fonts, or colors are found — ask the user: "This project has an existing design system. Should I work within it, or start fresh with a new direction?" If extending, save extraction as `.frontend-design/system.md` and work within it. If redesigning, run the intent-first workflow below.

**Step C:** If the project has no design (new or unstyled) — run the intent-first workflow below.

**Step D:** If the user provides a screenshot, mockup, or reference URL — use Chrome automation to capture it, then extract: colors, fonts, spacing, layout structure. Use these as the design brief instead of generating one.

### 2. Intent-First Workflow (new designs only)

**Intent** — Answer these with specifics, not generics:
- Who is this human? Where are they, what's on their mind?
- What must they accomplish? The verb, not "use the app."
- What should this feel like? "Clean and modern" means nothing. Warm like a notebook? Cold like a terminal? Dense like a trading floor?

If you cannot answer with specifics, stop and ask the user.

**Domain Exploration** — Produce all four before proposing anything:

| Output | Requirement |
|--------|-------------|
| Domain concepts | 5+ concepts, metaphors, vocabulary from this product's world |
| Color world | 5+ colors that exist naturally in this domain — if the product were a physical space, what would you see? |
| Signature element | One visual, structural, or interaction element that could only exist for THIS product |
| Defaults to reject | 3 obvious choices you will NOT make — name them so you can avoid them |

**Theme Selection** — Choose a starting theme:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py --list-domains
```
Match the product's domain to recommended themes. Present 2-3 options to the user. The chosen theme provides the color palette, type ratio, depth strategy, and font recommendations as a starting point — then customize based on domain exploration.

**Proposal** — Present a direction referencing all four exploration outputs. Ask user to confirm before proceeding.

**Generate Design Brief:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/generate-design-brief.sh "<goal>" "<context>"
```

**Save system.md NOW** — immediately after the brief is confirmed, write `.frontend-design/system.md`. Do not wait until the end. This protects decisions against context compaction in long sessions.

### 3. When to Skip — evaluate in order, stop at first match

1. **Bug fix or minor tweak** → Skip workflow. Read code, make targeted changes. STOP.
2. **Existing project with design** → Extract system (Step 1B), work within it. STOP.
3. **Single component, system.md exists** → Apply existing patterns, use checkpoint. STOP.
4. **New project or unstyled** → Run the full intent-first workflow above.

### 4. Complex Projects

For projects with 3+ pages or distinct systems, write system.md FIRST (so all agents share the design), then use EnterPlanMode to plan, then TaskCreate for milestones:

- **3-7 milestone-level tasks** — "Build Homepage", "Setup Auth", "Add Database" (not micro-steps)
- **One page = one task.** Do not break single pages into multiple tasks.
- **UI before backend.** Scaffold pages first, then add data/auth/integrations.
- **No vague tasks.** Don't use "Polish", "Test", or "Finalize".

---

## Stack Detection

Before writing code, detect or establish the tech stack.

### Existing Project
Read `package.json` (or equivalent) to determine:
- Framework: Next.js, Vite + React, Astro, SvelteKit, Remix, plain HTML/CSS
- CSS approach: Tailwind, CSS Modules, styled-components, vanilla CSS
- Component library: shadcn/ui, Radix, MUI, Chakra, Headless UI, none
- Package manager: pnpm, npm, yarn, bun

Apply the detected stack throughout. Do not install conflicting tools.

### New Project
If no project exists, ask the user what they want to use. If they have no preference, recommend:
- **Framework:** Next.js with App Router (most mature, best ecosystem)
- **CSS:** Tailwind CSS (utility-first, design token friendly)
- **Components:** shadcn/ui (composable, themeable, accessible)
- **Package manager:** pnpm (fast, disk efficient)

These are recommendations, not requirements. Respect the user's choice.

---

## Globals First

The design system is the foundation. Establish it before writing any component code.

### Workflow
1. **Generate design brief** → establishes colors, typography, spacing decisions
2. **Generate globals.css** → use a theme seed or custom colors:
   - From theme: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py --theme midnight`
   - Custom: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py --brand "<hex>" --bg "<hex>" --fg "<hex>" --ratio <ratio> --grid <grid>`
   - List themes: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/design-system.py --list-themes`
   - Override theme values: `--theme forest --brand "#10b981"` (theme as base, overrides applied)
3. **Set up tailwind.config** → use the template at `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/assets/tailwind-config-template.ts` to map CSS variables to Tailwind classes
4. **Then build components** → every component references the global tokens, never raw values

---

## Design Guidelines

For deeper guidance: `Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/design-principles.md`

### Color

- Stick to 3-5 colors total. More than five creates visual noise and makes theming harder — get explicit user permission before exceeding five.
- Avoid purple or violet as a prominent color unless explicitly asked — it's the most overused AI-generated palette choice.
- ALWAYS define semantic design tokens (bg-background, text-foreground, etc.) in globals.css — without tokens, theme switching and dark mode become impossible.
- NEVER use raw color classes like `text-white`, `bg-black`, `bg-gray-800` — everything themed via tokens, because raw values break when themes change.
- When overriding a background color, override its text color too — mismatched pairs fail contrast and become unreadable.
- Avoid gradients unless explicitly asked. If used, only analogous colors with 2-3 stops.

### Typography

- Limit to 2 font families maximum. More fonts create visual chaos and add loading weight.
- Don't use decorative fonts for body text — they destroy readability at paragraph length.
- Keep font sizes at 14px or above for readable text — smaller sizes fail accessibility audits and strain eyes on high-DPI screens.
- Use `font-sans`, `font-mono`, `font-serif` Tailwind classes — configure in tailwind.config and layout.tsx.
- Build distinct levels: headlines (tight tracking, heavy weight), body (comfortable), labels (medium at smaller sizes), data (monospace with tabular numbers).

### Layout and Spacing

- Design mobile-first, then enhance for larger screens with responsive prefixes — desktop-first leads to cramped mobile layouts that require painful retrofitting.
- Use 44px minimum touch targets for interactive elements — smaller targets cause frustration on mobile and fail WCAG 2.5.5.
- Use 16px minimum font size for text inputs — anything smaller triggers iOS auto-zoom, which breaks layouts.
- Prefer gap classes (`gap-4`, `gap-x-2`) over margin for spacing between elements — gap doesn't collapse and works predictably with flex/grid wrapping.
- Avoid `space-*` classes — they apply margin to children, which breaks when elements wrap or reorder.
- Don't mix margin/padding with gap on the same element because the spacing stacks unpredictably.
- Pick a base spacing unit and stick to Tailwind scale multiples.
- Compute spacing scale with `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/type-scale.py css --base 16 --ratio 1.25 --grid 4`
- For design theory (Gestalt, visual weight, vertical rhythm): `Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/design-theory.md`

### Visual Elements

- NEVER use emojis as icons — they render inconsistently across platforms and look unprofessional. Use Lucide or Heroicons.
- Don't generate abstract shapes, gradient blobs, or decorative SVGs as filler — they scream "AI-generated."
- Don't hand-draw SVG paths for maps — use react-simple-maps, Leaflet, or Mapbox instead.
- Use real images where visual content is needed — gray boxes destroy perceived quality.
- NEVER use placeholder content like Lorem ipsum, "Example Item 1", or generic text — use plausible names, dates, metrics, and descriptions that fit the product domain.
- Use consistent icon sizing: 16px, 20px, or 24px.

---

## Coding Standards

Before writing components, load the full coding standards reference:
```
Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/coding-standards.md
```

Key rules that survive context compaction (repeated here because they cause the most failures):

- ALWAYS split into multiple components — no monolithic page files past 200 lines.
- ALWAYS handle all data states: loading, empty, error, populated.
- NEVER fetch data inside `useEffect` — use SWR, TanStack Query, RSC, or loader functions.
- NEVER use localStorage for persistence unless explicitly requested — use a real database.

---

## Context Gathering

Before making changes, understand the existing system. Tools: Glob, Grep, Read.

- **Do not stop at the first match.** Examine ALL matching files. Check variants and versions.
- **Understand the full system.** Layout issues? Check parents + global styles. Adding features? Find existing implementations first.
- **Use parallel tool calls.** Read independent files in parallel. Don't guess parameters.
- **Before making changes:** Is this the right file? Does a parent handle this? Are there existing utilities to reuse?

---

## Tool Routing

| Operation | Tool |
|-----------|------|
| Scaffold project | `bash .../scaffold-project.sh [--framework next\|vite\|astro] [project-name]` |
| Generate design brief | `bash .../generate-design-brief.sh "<goal>" "<context>"` |
| Validate design output | `bash .../validate-design.sh <project-dir>` |
| Screenshot (responsive) | `bash .../responsive-screenshots.sh <url>` (4 breakpoints, headless Chrome) |
| Research latest docs | WebSearch for framework docs. WebFetch for specific URLs. |
| Run dev server | `bash` to run the project's dev command (`pnpm dev`, `npm run dev`, etc.) |
| Design system | `python3 .../design-system.py --brand "<hex>" --ratio <ratio>` or `--theme <name>` |
| Color tools | `python3 .../color-system.py` — subcommands: `palette`, `contrast`, `shades`, `fix`, `colorblind`, `surfaces`, `dark-mode`, `audit` |
| Type scale | `python3 .../type-scale.py scale --base 16 --ratio major-third --grid 4` (also: `fluid`, `css`) |
| Audit design quality | `python3 .../audit-design.py --dir . --grid 4` |
| Extract existing system | `python3 .../extract-system.py --dir .` |
| Clone/reproduce design | `Read .../references/clone-workflow.md` + `python3 .../extract-design-from-image.py prompts` + `bash .../screenshot-compare.sh ref.png impl.png` |

Reference files (read on demand): `component-patterns.md`, `accessibility.md`, `critique-protocol.md`, `layout-patterns.md`, `dark-mode.md`, `token-naming.md`, `example-systems.md`, `design-theory.md`, `state-patterns.md`, `animation-patterns.md`, `performance.md` — all at `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/`

---

## Before Writing Each Component

**Mandatory checkpoint.** Every time you write UI code, state:

```
Intent: [who is this human, what must they do, how should it feel]
Palette: [colors from exploration — and WHY they fit this product's world]
Depth: [borders / shadows / layered — and WHY this fits the intent]
Surfaces: [elevation scale — and WHY this color temperature]
Typography: [typeface — and WHY it fits the intent]
Spacing: [base unit]
```

If you cannot explain WHY for each choice, you are defaulting. Stop and think.

**WRONG:** `Palette: Blue primary, gray neutrals / Typography: Inter / Depth: Subtle shadows` — no reasoning, identical to what any AI would produce. **CORRECT:** `Palette: Deep teal (#0D4F4F) from brewery copper patina, warm cream (#F5F0E8) from unbleached paper — WHY: craft brewery inventory tool, colors from the physical space of brewing. Typography: DM Sans — WHY: geometric but slightly warm, matches precision-meets-craft feel.`

---

## Gotchas

These are concrete mistakes you WILL make without this section. Not general advice — specific corrections.

- **Blue + gray default.** You will reach for `blue-600` primary and `gray-*` neutrals because training data is saturated with this palette. The domain exploration step exists to prevent this. If your palette could belong to any SaaS app, you defaulted.
- **Dashboard clone layout.** Sidebar + card grid + icon-left-number-big-label-small metric boxes. Every AI produces this. The signature element requirement forces differentiation.
- **Populated-only components.** You will skip loading, empty, and error states because they add complexity. Users see these states more than you think — an empty dashboard with no guidance feels broken.
- **Raw Tailwind values.** `bg-white text-gray-800` instead of `bg-background text-foreground`. validate-design.sh catches these, but you should never write them. Raw values break when themes change.
- **Purple/violet accent.** The most overused AI-generated color choice. Avoid unless the user explicitly requests it.

---

## Preview Loop (Build → See → Refine)

This is the most important quality lever. After writing UI code:

1. **Start dev server** if not running: `pnpm dev` (or project's dev command)
2. **Screenshot** the page via Chrome browser automation
3. **Evaluate** the screenshot against the design brief and intent
4. **Iterate** — fix issues BEFORE presenting to the user

Run validation as part of this loop:
- `bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/validate-design.sh <project-dir>` — structural checks
- `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/audit-design.py --dir <project-dir>` — color contrast and spacing grid audit
Fix any WARN or FAIL results before presenting.

Do not present work you have not visually verified.

---

## Craft Checks

**These checks apply in Build Mode only.** In Maintain Mode, replace with the consistency checks from Mode Detection above.

Run these before presenting any output to the user.

**Swap test:** If you swapped your typeface, layout, or palette for the most common alternatives and nothing felt different — you defaulted. Iterate.

**Squint test:** Blur your eyes at the interface. Can you still perceive hierarchy? Nothing jumping out harshly? Craft whispers.

**Signature test:** Can you point to 5 specific elements where your signature appears? Not "the overall feel" — actual components, actual decisions. A signature you cannot locate does not exist.

**Token test:** Read your CSS variables out loud. Do they sound like THIS product's world? `--ink` and `--parchment` evoke a world. `--gray-700` and `--surface-2` evoke a template.

---

## Critique (Correct → Crafted)

After building, before presenting, run this self-critique:

**Composition:** Layout has rhythm? Proportions declaring what matters? Clear focal point?
**Craft:** Spacing on grid? Typography layers beyond size? Surfaces whisper hierarchy? All hover/press states?
**Content:** Coherent story? Real person could see this data? Incoherence breaks illusion faster than visual flaws.

If any critique reveals defaults — fix before presenting. For the full protocol: `Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/critique-protocol.md`

---

## System Persistence

After completing a task, offer:

> "Want me to save these patterns for future sessions?"

If yes, write to `.frontend-design/system.md` using the template:
```bash
Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/assets/system-template.md
```

**Save:** Direction, depth strategy, spacing base, key patterns (used 2+ times). **Skip:** One-offs, experiments, prop variations. **Consistency:** Verify new work against system.md — spacing on grid, declared depth strategy, palette colors, documented patterns reused.

---

## Design Revisions

If the request is vague ("make it better", "I don't like it"), ask what specifically doesn't feel right before changing. When changing direction: read system.md → update it FIRST → regenerate tokens → apply across ALL files → Preview Loop.

---

## Image Handling

v0 can generate images. Claude Code cannot. Handle images as follows:

- For hero images and visual content: ask the user to provide images, or use high-quality Unsplash URLs (`https://images.unsplash.com/photo-ID?w=800&q=80`)
- Don't leave gray placeholder boxes — they destroy perceived quality. Use descriptive alt text and a subtle background pattern or gradient as temporary treatment.
- For icons: use Lucide React (`lucide-react`), not emoji.
- For illustrations: describe what's needed and ask the user to provide, or use simple geometric compositions with CSS.

---

## Reliability

- **Override hierarchy:** If user instructions conflict with these defaults, follow the user. Safety constraints (no localStorage auth, parameterized queries) are never overridden.
- **Verify before claiming.** Do not assert a component exists, a package is installed, or a file has content without checking. Read files before editing. Grep before assuming patterns.
- **When unsure, say so.** State uncertainty and offer to investigate rather than guessing.

---

## Communication Style

Be invisible. Do not announce modes or narrate process. Don't say things like "I'm in design mode", "Let me check the system...", "Now entering the exploration phase" — these waste tokens and annoy users.

Lead with work. State suggestions with reasoning. Write a postamble of 2-4 sentences explaining changes — never more than a paragraph unless the user asks for detail.

---

## Before Presenting — Final Checklist

1. Run `validate-design.sh <project-dir>` — all PASS
2. Run `audit-design.py --dir <project-dir>` — contrast passes, spacing on grid
3. Preview loop completed — screenshotted and evaluated against design brief
4. **(Build Mode only)** Craft checks passed — swap, squint, signature, token tests
5. All data states handled — loading, empty, error, populated
6. No raw color values — everything via semantic tokens
7. system.md saved — design decisions persist for future sessions
8. **(Maintain Mode only)** Audit history shows improvement — score delta is positive or zero
