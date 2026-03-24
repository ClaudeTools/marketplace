---
title: "Designing Interfaces"
description: "Skill for building production-grade frontend interfaces with high design quality — React, Next.js, Vite, Astro, SvelteKit, and Tailwind CSS."
---
Build distinctive, production-grade frontend interfaces with high design quality. Covers React, Next.js, Vite, Astro, SvelteKit, Tailwind CSS, and plain HTML/CSS projects.

**Trigger:** Use when the user asks to build a website, landing page, dashboard, web app, UI component, page layout, or any visual web interface. Also use for redesigns, restyling, dark mode, or design system creation.

**Invocation:** `/frontend-design [description of what to build]`

---

## When to use this

Use this skill when you're building any visual interface from scratch — a landing page, dashboard, settings form, or component. It's also the right choice when you have an existing design and want to audit it, add dark mode, or bring it in line with a design system. If Claude is about to write UI code without a systematic approach to tokens, contrast, or responsiveness, invoke this first.

---

## Try it now

```
/designing-interfaces A billing dashboard with a summary card, recent invoices table, and usage chart
```

Claude will ask about your stack (or detect it from `package.json`), generate a CSS design system with semantic tokens, build the components, take responsive screenshots at 4 breakpoints, and run contrast and token audits before presenting the result.

---

## Modes

### Build Mode
Full creative workflow for new designs: intent exploration, domain exploration, theme selection, design brief, signature elements. Swap test, squint test, and signature test apply.

### Maintain Mode
For existing projects with an established design system. Consistency is the goal — new work should match existing patterns. Applies token consistency, pattern reuse, and regression checks instead of creative principles.

### Audit Mode (subset of Maintain)
When the user asks to audit or fix design quality. Runs `extract-system.py`, `validate-design.sh`, and `audit-design.py` in sequence, collates findings by severity, and offers to auto-fix eligible issues.

---

## Workflow Steps (Build Mode)

1. **Check for existing design** — look for `.frontend-design/system.md`. If found, apply it and skip to building.
2. **Intent-first exploration** — define who the user is, what they must do, what the product should feel like. Produce: domain concepts, color world, signature element, defaults to reject.
3. **Theme selection** — match domain to recommended themes via `design-system.py --list-domains`. Present 2-3 options.
4. **Generate design brief** — `generate-design-brief.sh "<goal>" "<context>"`
5. **Save system.md** immediately after brief is confirmed.
6. **Stack detection** — read `package.json` to determine framework, CSS approach, component library.
7. **Generate globals.css** — use `design-system.py` with chosen theme or custom colors.
8. **Build components** — all values reference global tokens, never raw Tailwind color classes.
9. **Preview loop** — screenshot via Chrome, evaluate against brief, iterate before presenting.
10. **Craft checks** — swap test, squint test, signature test, token test.

---

## Key Scripts

Located at `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/`:

| Script | Purpose |
|--------|---------|
| `design-system.py` | Generate CSS design system from brand color + theme seed |
| `color-system.py` | Contrast check, palette generation, color blindness simulation |
| `validate-design.sh` | Structural checks: tokens, raw colors, font count, alt text |
| `audit-design.py` | Contrast matrix, spacing grid, vertical rhythm, completeness score |
| `responsive-screenshots.sh` | Headless Chrome screenshots at 4 breakpoints |
| `scaffold-project.sh` | Initialize Next.js/Vite/Astro with design tokens |

---

## Design Rules (Key)

- Never use raw color classes (`text-white`, `bg-gray-800`) — always use semantic CSS custom property tokens.
- Limit to 3-5 colors total. No purple/violet unless explicitly requested.
- Limit to 2 font families maximum.
- Mobile-first with 44px minimum touch targets.
- Use `gap-*` classes, not `space-*` classes.
- Never use placeholder content — use plausible domain-specific data.
- Never use emojis as icons — use Lucide or Heroicons.

---

## Example Invocations

```
/frontend-design A SaaS billing dashboard with dark mode
/frontend-design Landing page for a craft brewery inventory tool
/frontend-design Audit and fix the design system on this project
/frontend-design Add a responsive nav component to the existing app
```

---

## Related Components

- **feedback_no_hardcoded_colors** memory — critical reminder about token usage
- **ui-verification rule** — all UI changes must be verified in Chrome after deployment
- **validate-design.sh** — run before presenting any UI work
