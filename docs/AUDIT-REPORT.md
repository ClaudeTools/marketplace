# Documentation Audit Report

**Date:** 2026-03-25
**Auditor:** Implementation agent
**Scope:** All content in `docs/src/content/docs/` — 58 files (57 `.md` + 1 `.mdx`)

---

## Section 1: Page Inventory Table

| Path | Title | Word Count | Has Prerequisites | Has Examples | Has Next Steps | Issues |
|------|-------|-----------|-------------------|--------------|----------------|--------|
| `index.md` | Documentation Index | 12 | No | No | No | Empty stub — table with no entries; conflicts with index.mdx |
| `index.mdx` | claudetools | 239 | No | No | No | Real homepage; duplicate with index.md above |
| `getting-started/installation.md` | Installation | 165 | No | Yes (code) | No (no "next steps" section) | Generic description; no intro paragraph; jumps straight to `## Install` |
| `getting-started/quick-tour.md` | Quick Tour | 664 | No | Yes | Yes | Good page; one broken outbound link (skills index) |
| `getting-started/core-concepts.md` | Core Concepts | 700 | No | Yes (code) | No | Generic description; "one more" agent unnamed in table; no links to deeper reference |
| `guides/build-a-feature.md` | Build a Feature | 822 | No | Yes | Yes | Broken link to `feature-pipeline/index.md` |
| `guides/coordinate-agents.md` | Coordinate Agents | 901 | No | Yes | Yes | No issues |
| `guides/debug-a-bug.md` | Debug a Bug | 910 | No | Yes | Yes | Broken link to `investigating-bugs/index.md` |
| `guides/design-a-ui.md` | Design a UI | 960 | No | Yes | Yes | No issues |
| `guides/explore-a-codebase.md` | Explore a Codebase | 771 | No | Yes | Yes | Generic description |
| `guides/improve-prompts.md` | Improve Prompts | 910 | No | Yes | Yes | Generic description; broken link to `../reference/skills.md` |
| `guides/manage-tasks.md` | Manage Tasks | 907 | No | Yes | Yes | No issues |
| `guides/review-code.md` | Review Code | 718 | No | Yes | Yes | Generic description; broken link to `../reference/skills.md` |
| `guides/run-security-audit.md` | Run a Security Audit | 894 | No | Yes | Yes | No issues |
| `guides/setup-new-project.md` | Set Up a New Project | 666 | No | Yes (inline) | Yes | Generic description; no intro paragraph |
| `guides/which-tool.md` | Which Tool Should I Use? | 737 | No | Yes (tables) | No | References `/build-a-feature` and `/debug-a-bug` slash commands that don't exist |
| `advanced/architecture.md` | Architecture | 553 | No | Yes (code) | No | Generic description; no intro paragraph; no "next steps" or related links |
| `advanced/configuration.md` | Configuration | 429 | No | Yes (code) | No | Generic description; no intro paragraph |
| `advanced/extending.md` | Extending | 632 | No | Yes (code) | No | Generic description; no intro paragraph |
| `advanced/shared-libraries.md` | Shared Libraries | 682 | No | Yes | No | Generic description; all code blocks unannotated (no language tags) — 35+ instances |
| `advanced/telemetry.md` | Telemetry | 357 | No | Yes (code) | No | Generic description; no intro paragraph |
| `advanced/troubleshooting.md` | Troubleshooting | 608 | No | Yes | No | Generic description; no intro paragraph |
| `advanced/validators.md` | Validators | 777 | No | Yes (code) | No | Generic description; no intro paragraph |
| `reference/agent-mesh.md` | Agent Mesh | 482 | No | Yes | No | Generic description; no intro paragraph |
| `reference/rules.md` | Rules | 552 | No | No | No | Generic description; no code examples; no links to usage guides |
| `reference/task-system.md` | Task System | 421 | No | Yes | No | Generic description; no intro paragraph |
| `reference/agents/index.md` | Agents | 195 | No | No | No | Generic description; no intro paragraph; links use `/reference/agents/feature-pipeline/` path pattern (requires trailing slash) |
| `reference/agents/architect.md` | Architect | 285 | No | Yes | No | Generic description |
| `reference/agents/bugfix-pipeline.md` | Bugfix Pipeline | 375 | No | Yes | No | Generic description |
| `reference/agents/code-reviewer.md` | Code Reviewer | 305 | No | Yes | No | Generic description |
| `reference/agents/feature-pipeline.md` | Feature Pipeline | 325 | No | Yes | No | Generic description |
| `reference/agents/implementing-features.md` | Implementing Features | 297 | No | Yes | No | Generic description |
| `reference/agents/refactor-pipeline.md` | Refactor Pipeline | 345 | No | Yes | No | Generic description |
| `reference/agents/researcher.md` | Researcher | 357 | No | Yes | No | Generic description |
| `reference/agents/security-pipeline.md` | Security Pipeline | 319 | No | Yes | No | Generic description |
| `reference/agents/test-writer.md` | Test Writer | 302 | No | Yes | No | Generic description |
| `reference/codebase-pilot/cli-reference.md` | CLI Reference | 374 | No | Yes | No | Generic description; "FTS5", "DFS" undefined; no intro paragraph |
| `reference/codebase-pilot/indexing.md` | Indexing | 269 | No | No | No | Generic description; "WAL mode" undefined |
| `reference/codebase-pilot/supported-languages.md` | Supported Languages | 216 | No | Yes | No | Generic description; "WASM" not spelled out on first use |
| `reference/commands/claude-code-guide.md` | /claude-code-guide | 195 | No | Yes | No | Generic description |
| `reference/commands/code-review.md` | /code-review | 179 | No | Yes | No | Generic description |
| `reference/commands/docs-manager.md` | /docs-manager | 161 | No | Yes | No | Generic description; shortest command page — very thin |
| `reference/commands/field-review.md` | /field-review | 263 | No | Yes | No | Generic description |
| `reference/commands/logs.md` | /logs | 209 | No | Yes | No | Generic description |
| `reference/commands/memory.md` | /memory | 302 | No | Yes | No | Generic description |
| `reference/commands/mesh.md` | /mesh | 308 | No | Yes | No | Generic description |
| `reference/commands/session-dashboard.md` | /session-dashboard | 208 | No | Yes | No | Generic description |
| `reference/hooks/index.md` | Hooks | 268 | No | No | No | Generic description; links to hook category pages use absolute paths that may not resolve |
| `reference/hooks/context-hooks.md` | Context Hooks | 418 | No | No | No | Generic description; no code examples showing hook effect; no intro paragraph |
| `reference/hooks/process-hooks.md` | Process Hooks | 368 | No | No | No | Generic description; no code examples |
| `reference/hooks/quality-hooks.md` | Quality Hooks | 321 | No | No | No | Generic description; no code examples |
| `reference/hooks/safety-hooks.md` | Safety Hooks | 338 | No | No | No | Generic description; no code examples |
| `reference/skills/designing-interfaces.md` | Designing Interfaces | 553 | No | Yes | No | Generic description |
| `reference/skills/evaluating-safety.md` | Evaluating Safety | 351 | No | Yes | No | Generic description |
| `reference/skills/exploring-codebase.md` | Exploring Codebase | 387 | No | Yes | No | Generic description |
| `reference/skills/investigating-bugs.md` | Investigating Bugs | 375 | No | Yes | No | Generic description |
| `reference/skills/managing-tasks.md` | Managing Tasks | 383 | No | Yes | No | Generic description |
| `reference/skills/plugin-improver.md` | Improving Plugin | 378 | No | Yes | No | Generic description; title mismatch — file is `plugin-improver.md`, title is "Improving Plugin" |
| `reference/skills/prompt-improver.md` | Improving Prompts | 368 | No | Yes | No | Generic description; title mismatch — file is `prompt-improver.md`, title is "Improving Prompts" |

---

## Section 2: Broken Internal Links

All broken links found by verifying that the target `.md` file exists relative to the source file's directory.

| Source File | Line | Link Text | Target Path | Problem |
|-------------|------|-----------|-------------|---------|
| `getting-started/quick-tour.md` | 115 | "Skills Reference" | `../../reference/skills/index.md` | No file at `reference/skills/index.md` — the skills directory has individual skill pages but no `index.md` |
| `guides/build-a-feature.md` | 157 | "Reference: feature-pipeline agent" | `../../reference/agents/feature-pipeline/index.md` | No subdirectory `feature-pipeline/` — the page is at `reference/agents/feature-pipeline.md` |
| `guides/debug-a-bug.md` | 147 | "Reference: investigating-bugs skill" | `../../reference/skills/investigating-bugs/index.md` | No subdirectory `investigating-bugs/` — the page is at `reference/skills/investigating-bugs.md` |
| `guides/improve-prompts.md` | 152 | "Reference: prompt-improver skill" | `../reference/skills.md` | No file at `reference/skills.md` — the page is at `reference/skills/prompt-improver.md` |
| `guides/review-code.md` | 132 | "Reference: code-review skill" | `../reference/skills.md` | No file at `reference/skills.md` — skills are individual pages under `reference/skills/` |

**Summary: 5 broken links across 5 files.**

**Note on `reference/agents/index.md`:** This file uses absolute URL paths like `/reference/agents/feature-pipeline/` (with trailing slashes) rather than relative `.md` links. Astro Starlight may resolve these via URL routing, but they differ from the `.md` file path convention used elsewhere and could break in certain deploy configurations.

---

## Section 3: Undefined Technical Terms

Terms used without definition that a beginner to Claude Code or the claudetools plugin would not know.

| Term | First Used In | Problem |
|------|--------------|---------|
| `tree-sitter` | `getting-started/core-concepts.md` | Proper noun for a parsing library; used as if known ("Tree-sitter + SQLite indexing engine") with no explanation of what it does |
| `FTS5` | `reference/codebase-pilot/cli-reference.md` | SQLite full-text search extension; used in "FTS5 prefix search" without expansion |
| `WAL mode` | `reference/codebase-pilot/indexing.md` | SQLite Write-Ahead Logging; used as "SQLite with WAL mode" without explanation |
| `WASM` | `reference/codebase-pilot/supported-languages.md` | WebAssembly; heading reads "WASM (lazy-loaded)" without spelling it out on first use |
| `DFS` | `reference/codebase-pilot/cli-reference.md` | Depth-First Search; used in `circular-deps` description: "via DFS graph traversal" |
| `PreToolUse` / `PostToolUse` | `reference/hooks/index.md` | Claude Code lifecycle event names; used extensively in hooks documentation without a glossary entry or link to Claude Code docs explaining the event model |
| `SessionStart` / `SessionEnd` / `Stop` / `TeammateIdle` | `reference/hooks/index.md` | Same — Claude Code lifecycle events used with no pointer to what they mean |
| `TeamCreate` | `guides/coordinate-agents.md` | Claude Code tool name; used repeatedly without defining what it is or linking to Claude Code docs |
| `two-strike rule` | `guides/debug-a-bug.md` | Domain-specific rule introduced inline in a guide; `core-concepts.md` doesn't define it, and `debug-a-bug.md` cross-references `core-concepts.md` as if it does |
| `hooks.json` | `advanced/architecture.md` | Plugin config format; first reference assumes familiarity with the Claude Code hooks system |
| `BATS` | Mentioned only in CLAUDE.md | The test framework used for shell tests; not mentioned or explained anywhere in user-facing docs |
| `MCP` | `getting-started/core-concepts.md` (Task System section) | "MCP-based persistent task tracking" — MCP (Model Context Protocol) never defined |
| `context compaction` | `reference/hooks/context-hooks.md` | Claude Code concept (context window compression); used in `archive-before-compact` hook without explanation |
| `SWE-bench` | `reference/skills/evaluating-safety.md` | External benchmark suite; used without linking to the source or defining what it measures |

---

## Section 4: Structural Issues

### 4a. Pages Missing Frontmatter `description` (Meaningful Content)

All 58 pages have a `description:` field, but 43 use the generic placeholder pattern `"X — claudetools documentation."` which provides no useful information for search engines or link previews. Pages with **useful** descriptions (fewer than half):

**Good descriptions (12 pages):**
- `index.mdx` — "Zero-config guardrails, skills, and agent pipelines for Claude Code."
- `getting-started/quick-tour.md` — "Your first five minutes with claudetools..."
- `guides/build-a-feature.md` — "Walk through a real feature build..."
- `guides/coordinate-agents.md` — "Run multiple Claude agents in parallel..."
- `guides/debug-a-bug.md` — "Walk through a real bug investigation..."
- `guides/design-a-ui.md` — "Build production-grade interfaces..."
- `guides/manage-tasks.md` — "Track work across sessions..."
- `guides/run-security-audit.md` — "Scan for secrets, injection vulnerabilities..."
- `guides/which-tool.md` — "Decision guide — pick the right claudetools skill for your task."
- `getting-started/installation.md` — *(marginally better than pattern: "Installation — claudetools documentation.")*

**Generic placeholder descriptions (46 pages):** All `advanced/`, all `reference/` pages, `getting-started/core-concepts.md`, `getting-started/installation.md`, `guides/explore-a-codebase.md`, `guides/improve-prompts.md`, `guides/review-code.md`, `guides/setup-new-project.md`.

### 4b. Duplicate Index Files

**Both files exist:**
- `docs/src/content/docs/index.md` — 12 words; contains only a markdown table header with no rows
- `docs/src/content/docs/index.mdx` — 239 words; the real Starlight homepage with hero, cards, and links

**Problem:** Astro Starlight will attempt to render both. Depending on resolution order, `index.md` (the empty stub) may override `index.mdx` (the real page) or cause a build conflict. The `index.md` is clearly a leftover from an earlier migration state.

**Fix:** Delete `docs/src/content/docs/index.md`.

### 4c. Heading Hierarchy Violations

No heading level skips (h1→h3) were found in the Astro content pages. However, some structural concerns:

- `advanced/shared-libraries.md`: Uses `##` as the only heading level for all entries — the page lists many libraries without grouping or h3 subheadings for individual functions, making it hard to scan.
- `reference/hooks/index.md`: Uses `##` and `- **Bold**` bullets rather than h3 for hook categories — inconsistent with the individual hook pages that use `##` per hook.

### 4d. Code Blocks Without Language Annotations

**`advanced/shared-libraries.md`** is the worst offender: lines 6–69 show 35+ consecutive unannotated code blocks (each function signature on its own ` ``` ` block). These blocks contain shell-like function signatures with no language tag, so syntax highlighting is disabled.

Other files with unannotated blocks:
- `getting-started/installation.md` lines 7–9 and 34–36: Two code blocks with no language tag (they contain `/plugin install claudetools@...` commands — should be `bash`)
- `guides/setup-new-project.md`: The inline prompt examples (`explore this codebase`, `/session-dashboard`) use unannotated code blocks
- `guides/which-tool.md` line 41: `/debug-a-bug` in a table cell — not a code block issue, but references a nonexistent slash command

---

## Section 5: Jekyll Remnant Files

The following files and directories exist under `docs/` but are **not** part of the Astro Starlight site (not under `docs/src/`, not standard Astro files). They are left over from a Jekyll migration.

| Path | Type | Contents | Action |
|------|------|----------|--------|
| `docs/index.md` | File | Jekyll front matter (`layout: home`, `title: claudetools`, `nav_order: 1`) followed by no content | Delete |
| `docs/advanced/` | Directory | 8 files: `index.md` + 7 topic pages (`architecture.md`, `configuration.md`, etc.) with Jekyll front matter (`parent: Advanced`, `nav_order: N`) | Delete entire directory |
| `docs/getting-started/` | Directory | 4 files: `index.md` + `core-concepts.md`, `installation.md`, `quick-tour.md` with Jekyll front matter | Delete entire directory |
| `docs/guides/` | Directory | 12 files: `index.md` + 11 guide pages with Jekyll front matter | Delete entire directory |
| `docs/reference/` | Directory | Recursive structure: `index.md` + subdirectories for `agents/`, `commands/`, `hooks/`, `skills/`, `codebase-pilot/`, plus individual pages | Delete entire directory |
| `docs/docs/` | Directory | Nested duplicate: contains `index.md` (empty) + `src/` subdirectory; `src/` appears to be a nested duplicate of the Astro content tree | Delete entire directory |
| `docs/assets/` | Directory | Contains `images/` subdirectory | **Check before deleting** — if `docs/src/styles/custom.css` or any Astro component references `../assets/images/`, images would break. If unused, delete. |

**Verification for `docs/assets/`:**
```bash
grep -r "assets/images" docs/src/
```
If no results, the directory is safe to delete.

**Total Jekyll remnant file count:** Approximately 35–40 files across 6 directories.

---

## Section 6: Top 10 Most Impactful Improvements

Prioritized by impact on user experience and site correctness.

### 1. Fix the 5 broken internal links (Critical — pages 404 on click)

Every broken link is in a guide page's "Related" section, meaning users who finish a guide and click to go deeper hit a dead end. Fix each:

| Broken | Fix to |
|--------|--------|
| `../../reference/skills/index.md` | Create `reference/skills/index.md` OR change to `../../reference/skills/exploring-codebase.md` |
| `../../reference/agents/feature-pipeline/index.md` | `../../reference/agents/feature-pipeline.md` |
| `../../reference/skills/investigating-bugs/index.md` | `../../reference/skills/investigating-bugs.md` |
| `../reference/skills.md` (×2) | `../reference/skills/prompt-improver.md` and `../reference/skills/prompt-improver.md` |

### 2. Delete `docs/src/content/docs/index.md` (Critical — may break homepage)

The empty `index.md` stub conflicts with the real `index.mdx` homepage. Astro Starlight's behavior with duplicate index files is undefined — this could render the empty page instead of the hero page. Delete `docs/src/content/docs/index.md` immediately.

### 3. Delete the 6 Jekyll remnant directories (High — repo pollution, CI confusion)

`docs/advanced/`, `docs/getting-started/`, `docs/guides/`, `docs/reference/`, `docs/docs/`, and `docs/index.md` are dead weight. They can confuse contributors who edit the wrong file (Jekyll version instead of Astro version). After verifying `docs/assets/` is unused, delete that too.

### 4. Create `reference/skills/index.md` (High — broken link target + missing overview page)

The skills reference section has no index page. `quick-tour.md` links to it, and it's a natural navigation target. Create a page that lists all 7 skills with one-line descriptions and links — mirror the pattern from `reference/agents/index.md`.

### 5. Fix the 46 generic `description:` values (Medium — SEO and link preview quality)

Pages with `"X — claudetools documentation."` descriptions show nothing useful in Google results or Slack unfurls. Each description should describe what the page teaches:

- `advanced/architecture.md` → "How claudetools is structured — dispatcher pattern, event-to-script mapping, and directory layout."
- `reference/hooks/index.md` → "51 hooks across 17 Claude Code lifecycle events — safety, quality, process, and context categories."
- Etc.

### 6. Add language annotations to all unannotated code blocks (Medium — readability)

`advanced/shared-libraries.md` has 35+ code blocks with no language tag. Add `bash` for shell commands and function signatures. All `/plugin install ...` blocks in `installation.md` and `quick-tour.md` should be `bash`. This is a mechanical find-and-replace.

### 7. Define technical terms in a glossary or on first use (Medium — accessibility for new users)

Add a "Glossary" page or inline definitions for: `tree-sitter`, `FTS5`, `MCP`, `WAL mode`, `WASM`, `TeamCreate`, `PreToolUse`/`PostToolUse`/`SessionStart` (link to Claude Code docs). The `getting-started/core-concepts.md` page is the right place for most of these.

### 8. Fix the "one more" unnamed agent in `core-concepts.md` (Medium — factual error)

`getting-started/core-concepts.md` line 75: "Standalone agents: `architect`, `implementing-features`, `code-reviewer`, `test-writer`, `researcher`, `investigating-bugs`, and one more." The missing agent is `exploring-codebase` (it exists as a reference page). Name it.

### 9. Add "Next Steps" sections to all `advanced/` and `reference/` pages (Low — navigation)

None of the 7 `advanced/` pages and none of the reference pages have "Related" or "Next Steps" sections. Users who read `advanced/architecture.md` have no path forward. At minimum, add 2–3 cross-links per page pointing to related guides or reference pages.

### 10. Fix title/filename mismatches in skills reference (Low — minor confusion)

- `reference/skills/plugin-improver.md` has title "Improving Plugin" — inconsistent with skill invocation name `/plugin-improver`
- `reference/skills/prompt-improver.md` has title "Improving Prompts" — inconsistent with skill invocation `/prompt-improver`

These titles don't match the sidebar label users would expect based on the slash command name. Change titles to "Plugin Improver" and "Prompt Improver" to match the invocation names.
