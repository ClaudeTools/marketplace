# Frontend Design (Compact)

> This is the compact version. For full creative workflow, invoke with `/frontend-design build`

Build and maintain production-grade frontend interfaces. Covers React, Next.js, Vite, Astro, SvelteKit, Tailwind CSS, and plain HTML/CSS.

## Mode

- **Maintain** (default in compact): Fix, wire, refactor, update existing UI within an established design system.
- **Build**: New pages, redesign, new project. Requires full SKILL.md — invoke `/frontend-design build`.

## Scripts

All at `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/`:

| Script | Use |
|--------|-----|
| `validate-design.sh <dir>` | Structural checks: tokens, raw colors, font count, alt text |
| `audit-design.py --dir <dir>` | Contrast matrix, spacing grid, vertical rhythm |
| `extract-system.py --dir .` | Scan existing project into system.md draft |
| `design-system.py --theme <name>` | Generate CSS design system from theme/brand color |
| `color-system.py` | Palette, contrast, shades, fix, colorblind, audit |
| `type-scale.py` | Modular scale, fluid typography, baseline grid |

## Key Constraints

- NEVER use raw color classes (`text-white`, `bg-gray-800`) — always use semantic tokens from globals.css.
- NEVER use emojis as icons — use Lucide or Heroicons.
- NEVER use placeholder content (Lorem ipsum, "Example Item 1") — use plausible domain-specific data.
- NEVER fetch data inside `useEffect` — use SWR, TanStack Query, RSC, or loader functions.
- NEVER use localStorage for persistence unless explicitly requested.
- Split components at 200 lines. Handle all data states: loading, empty, error, populated.
- Prefer `gap-*` over `space-*` or margin for element spacing.
- 44px minimum touch targets. 16px minimum input font size (prevents iOS auto-zoom).
- Limit to 2 font families, 3-5 colors. Avoid purple/violet unless requested.

## Context Gathering

Before making changes: read the target files, check `.frontend-design/system.md` if it exists, understand parent layouts. Use parallel tool calls for independent reads.

## Maintain Mode Checks

- **Token consistency** — all values reference system.md tokens, no raw values.
- **Pattern reuse** — new components follow existing patterns in the codebase.
- **Regression check** — no existing functionality broken.

## Verification

1. `bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/validate-design.sh <project-dir>` — all PASS
2. `python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/audit-design.py --dir <project-dir>` — contrast passes, spacing on grid
3. No raw color values in changed files.
4. All data states handled in new/changed components.

## References (read on demand)

All at `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/`: `coding-standards.md`, `design-principles.md`, `component-patterns.md`, `accessibility.md`, `layout-patterns.md`, `dark-mode.md`, `token-naming.md`, `state-patterns.md`, `animation-patterns.md`, `performance.md`
