---
title: "Contributing to Docs"
description: "How to run the docs locally, add new pages, follow style guidelines, and submit a pull request."
sidebar:
  order: 7
---

The claudetools docs are built with [Astro Starlight](https://starlight.astro.build/). All source files are in `docs/src/content/docs/`.

---

## Run locally

```bash
cd docs
npm install
npm run dev
```

Open [http://localhost:4321/marketplace/](http://localhost:4321/marketplace/) to see the site. Changes to `.md` files hot-reload automatically.

To verify a production build before submitting:

```bash
cd docs
npx astro build
```

---

## File structure

```
docs/
├── src/
│   ├── content/
│   │   └── docs/
│   │       ├── getting-started/   # Installation, quick tour, core concepts, FAQ
│   │       ├── guides/            # Task-oriented walkthroughs and tutorials
│   │       ├── reference/
│   │       │   ├── commands/      # Slash command reference pages
│   │       │   ├── skills/        # Skill reference pages
│   │       │   ├── agents/        # Agent reference pages
│   │       │   ├── hooks/         # Hook category pages
│   │       │   └── codebase-pilot/ # CLI reference
│   │       └── advanced/          # Architecture, configuration, extending, contributing
│   └── styles/
│       └── custom.css
├── astro.config.mjs               # Sidebar configuration
└── package.json
```

---

## Add a new page

**1. Create the file** in the appropriate directory:

```bash
# Example: a new guide
touch docs/src/content/docs/guides/my-workflow.md
```

**2. Add frontmatter** at the top:

```markdown
---
title: "My Workflow"
description: "One sentence describing what this page covers."
sidebar:
  order: 13
---
```

- `title` — shown in the browser tab and sidebar
- `description` — shown in search results and meta tags
- `sidebar.order` — controls position within the section (lower = higher up)

**3. Register in the sidebar** (for manually-ordered sections):

Open `docs/astro.config.mjs` and add your slug to the appropriate section:

```js
items: [
  // existing items...
  { slug: 'guides/my-workflow' },
],
```

Sections using `autogenerate` (Skills, Slash Commands, Agents, Hooks, Codebase Pilot, Advanced) pick up new files automatically — no config change needed.

**4. Build and verify:**

```bash
cd docs && npx astro build 2>&1 | tail -10
```

---

## Style guidelines

### Tone

- Direct, present-tense prose. "Claude reads the file" not "Claude will read the file".
- Short sentences. One idea per sentence.
- No filler ("In this section, we will..."). Start with the content.
- Address the reader as "you". Claude is "Claude", not "the AI" or "the model".

### Callouts

Use Starlight's built-in callout syntax:

```markdown
:::note[Prerequisites]
- Item one
- Item two
:::

:::tip[When to use what]
Guidance on choosing between options.
:::

:::caution[Important caveat]
Something the user must not overlook.
:::
```

Use `note` for prerequisites and background context. Use `tip` for decision guidance. Use `caution` for gotchas that cause real problems.

### Code blocks

Always include a language identifier:

````markdown
```bash
codebase-pilot map
```

```typescript
const user = await getUser(id);
```
````

For inline references to files, commands, and symbols: use backticks — `file.ts`, `codebase-pilot`, `UserService`.

### Links

Use relative links between docs pages:

```markdown
See [Core Concepts](../getting-started/core-concepts.md) for background.
See [Cheat Sheet](../reference/cheat-sheet.md) for the full list.
```

Do not use absolute URLs for internal links — they break when the `base` path changes.

### Frontmatter requirements

Every page must have `title` and `description`. The `description` is used in search results — make it specific enough to be useful out of context.

---

## Submit a PR

1. Fork the repo on GitHub: [ClaudeTools/marketplace-dev](https://github.com/ClaudeTools/marketplace-dev)
2. Create a branch: `git checkout -b docs/my-change`
3. Make your changes in `docs/src/content/docs/`
4. Verify the build: `cd docs && npx astro build`
5. Open a pull request against `main`

CI runs `astro build` on every PR. The PR will be blocked if the build fails.

For substantial additions (new sections, restructuring), open an issue first to align on scope before writing.

---

## See also

- [Astro Starlight docs](https://starlight.astro.build/) — full reference for callouts, components, and configuration
- [What's New](../reference/whats-new.md) — recent changes to the plugin these docs cover
- [Cheat Sheet](../reference/cheat-sheet.md) — source data for the reference tables
