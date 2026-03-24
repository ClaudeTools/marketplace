---
title: "Explore a Codebase"
description: "Explore a Codebase — claudetools documentation."
---
Use the exploring-codebase skill to navigate unfamiliar code, locate symbols, trace dependency chains, and map project architecture — without reading every file manually.


## What you need
- claudetools installed
- A codebase indexed by codebase-pilot (indexing runs automatically at session start)

## Steps

### 1. Get a project overview (map mode)

Start any unfamiliar codebase with a map:

```
explore this codebase
```

or ask Claude directly:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
```

The map shows languages, directory structure, entry points, and key exports. Use it to orient before diving into specifics.

### 2. Find where something is defined (find mode)

```
where is handleAuth defined?
```

Claude runs:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "handleAuth"
# Filter by kind: function, class, interface, type, variable, enum, method, property
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "handleAuth" --kind function
```

After finding the symbol, Claude automatically runs `file-overview` on the containing file to show surrounding context.

### 3. Understand a file or module (explore mode)

```
how does src/api/auth.ts work?
```

Claude runs two commands in sequence:

```bash
# See all symbols exported from the file
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "src/api/auth.ts"

# Find files connected via imports
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "src/api/auth.ts"
```

### 4. Trace who calls something (trace mode)

```
what uses the processPayment function?
```

Claude follows the usage chain:

```bash
# Find all files that import the symbol
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-usages "processPayment"

# For each importing file, see what it does with it
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "<importing-file>"
```

### 5. Trace a field through the codebase (trace-field mode)

```
where does amount_due get transformed?
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/trace-field.sh "amount_due"
```

Output is grouped by role: definitions, transforms, queries (SQL/ORM), and display (frontend rendering).

### 6. Find a route's handler (find-route mode)

```
which handler serves GET /api/v1/dashboard?
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/find-route.sh "/api/v1/dashboard"
```

Shows the full chain: route registration, handler function, middleware, and database calls.

### 7. Find dead code (dead-code mode)

```
what exports are never imported?
```

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js dead-code
```

### 8. Analyse change impact (change-impact mode)

```
what breaks if I change handleAuth?
```

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js change-impact "handleAuth"
```

Separates direct importers from test files so you can see the real blast radius before refactoring.

## What happens behind the scenes

- **codebase-pilot** maintains a persistent index of symbols, files, and import graphs — built at session start by `session-index.sh`
- Each mode chains multiple CLI commands to give a deeper picture than any single command would
- If recently edited files are missing from results, Claude runs `index-file <path>` to update the index incrementally without a full rebuild
- The **security-scan** and **dead-code** modes use the same index so they do not need to re-parse source files

## Tips

- Start every unfamiliar codebase with `map` — the overview guides all subsequent queries
- For a bug investigation, use: `find-symbol` (locate the error source) → `file-overview` (context) → `find-usages` (all call sites)
- Use `change-impact` before any refactor that touches exported symbols — know the blast radius first
- If results seem stale after editing files, ask Claude to reindex: "reindex the codebase" triggers a full rebuild

## Related

- [Debug a Bug](debug-a-bug.md) — uses explore modes as part of the OBSERVE step
- [Build a Feature](build-a-feature.md) — feature-pipeline runs exploration before planning
- [Run a Security Audit](run-security-audit.md) — security-scan mode finds vulnerabilities
