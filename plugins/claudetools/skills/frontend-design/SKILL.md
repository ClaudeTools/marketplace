---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build a website, landing page, dashboard, web app, UI component, page layout, or any visual web interface. Also use when asked to redesign, restyle, make something look better, add dark mode, or create a design system. Covers React, Next.js, Vite, Astro, SvelteKit, Tailwind CSS, and plain HTML/CSS projects.
argument-hint: [description of what to build]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch, TaskCreate, TaskUpdate, AskUserQuestion
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

When the user asks to audit, fix design issues, or improve design consistency in an existing project.

`Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/audit-mode.md` for the full 5-step workflow.

Quick reference: run `extract-system.py`, `validate-design.sh`, then `audit-design.py` in sequence → collate by severity (FAIL > WARN > INFO) → categorize auto-fixable vs manual → use AskUserQuestion multiSelect if multiple categories → re-audit after fixes, confirm positive score delta.

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

**Domain Exploration** — Produce all four before proposing: (1) 5+ domain concepts/metaphors, (2) 5+ colors from the physical world of this product, (3) one signature element that could only exist for THIS product, (4) 3 obvious defaults you will NOT use.

**Theme Selection** — Run `design-system.py --list-domains`, match to recommended themes, then use AskUserQuestion with `preview` (single-select, 2-3 options). Each option: label = theme name, description = domain mood, preview = real hex palette (██ chars), font pairing, depth strategy, and signature element — all from actual script output. Never use example palettes.

**Proposal** — Present a direction referencing all four exploration outputs. Ask user to confirm, then run `generate-design-brief.sh "<goal>" "<context>"`.

**Save system.md NOW** — write `.frontend-design/system.md` immediately after the brief is confirmed. Do not wait — context compaction will lose decisions.

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

Read `package.json` to detect framework (Next.js, Vite+React, Astro, SvelteKit, Remix), CSS approach (Tailwind, CSS Modules, vanilla), component library (shadcn/ui, Radix, MUI, none), and package manager. Apply throughout — do not install conflicting tools.

If no project exists, ask the user. Default recommendation: Next.js App Router + Tailwind CSS + shadcn/ui + pnpm. These are suggestions, not requirements.

---

## Globals First

Establish the design system before writing any component code:

1. Generate design brief
2. Generate `globals.css` via `design-system.py --theme <name>` or `--brand <hex> --bg <hex> --fg <hex>` (use `--list-themes` to browse; mix e.g. `--theme forest --brand "#10b981"`)
3. Set up `tailwind.config` from `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/assets/tailwind-config-template.ts`
4. Build components — always reference global tokens, never raw values

---

## Design Guidelines

`Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/design-principles.md`

Critical safety rules (repeated here because they cause the most failures):

- NEVER use raw color classes (`text-white`, `bg-black`, `bg-gray-800`) — everything via semantic tokens; raw values break when themes change.
- ALWAYS override the text color when overriding a background — mismatched pairs fail contrast.
- NEVER use emojis as icons — use Lucide or Heroicons instead.
- NEVER use placeholder content (Lorem ipsum, "Example Item 1") — use plausible domain-appropriate content.
- Stick to 3-5 colors total; get explicit permission before exceeding five.
- For design theory: `Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/design-theory.md`

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

Before making changes: examine ALL matching files (not just the first match), check parents and global styles, find existing implementations before adding new ones. Use parallel tool calls for independent reads. Before editing: confirm this is the right file, check if a parent handles it, look for utilities to reuse.

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

`Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/craft-checks.md` for the full checkpoint, gotchas, craft tests, and self-critique protocol.

**Minimum required:** state Intent, Palette (with WHY), Depth (with WHY), Typography (with WHY), Spacing before writing any UI code. If you cannot explain WHY for each choice, you are defaulting.

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

## Craft Checks and Critique

`Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/craft-checks.md` for the full craft check protocol (swap test, squint test, signature test, token test) and the self-critique framework.

These checks apply in **Build Mode only** — run before presenting any output.

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
