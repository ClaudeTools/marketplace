---
name: exploring-codebase
description: Explores codebase structure, finds symbol definitions, traces dependency chains, and maps project architecture. Use when understanding unfamiliar code, finding where something is defined, tracing what calls a function, exploring how a module works, navigating dependencies, or getting a project overview.
argument-hint: [query or file path]
allowed-tools: Read, Bash, Grep, Glob
metadata:
  author: Owen Innes
  version: 1.1.0
  category: navigation
  tags: [explore, find, trace, navigate, symbols, architecture, dependencies]
---

# Exploring Codebase

Structured codebase navigation using the codebase-pilot CLI. This skill wraps the CLI into workflow modes that chain commands for deeper understanding.

The CLI path: `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js`

For the full command reference table, see the `codebase-navigation` rule file. This skill focuses on **when and how** to chain commands, not repeating the reference.

## Mode Selection

Before running commands, determine the right mode based on the user's intent:

| User Intent | Mode | Commands Used |
|-------------|------|---------------|
| "How is this project structured?" / "Give me an overview" | **map** | `map` |
| "Where is X defined?" / "Find the function Y" | **find** | `find-symbol`, then `file-overview` on the result |
| "How does this file/module work?" / "What does X depend on?" | **explore** | `file-overview` + `related-files` |
| "What uses X?" / "Trace the dependency chain for Y" | **trace** | `find-usages` + `related-files` on each result |
| Free-form question about the codebase | **navigate** | `navigate` (query-driven search) |

## Mode: map

Get a high-level project overview — languages, structure, entry points, key exports.

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
```

Use this as the first step when entering an unfamiliar codebase. Read the output to understand the project's shape before diving into specifics.

**When to chain further:** After `map`, use `file-overview` on key entry points or files that look relevant to the user's question.

## Mode: find

Locate a symbol (function, class, type, variable) by name.

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "$ARGUMENTS"
```

Optionally filter by kind:
```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "$ARGUMENTS" --kind function
```

Kinds: `function`, `class`, `interface`, `type`, `variable`, `enum`, `method`, `property`.

**When to chain further:**
1. After finding the symbol, run `file-overview` on the file to see surrounding context
2. Run `related-files` to understand what imports or depends on that file
3. Read the actual file at the symbol's line number for implementation details

## Mode: explore

Understand a specific file or module — what it exports, what it imports, and what connects to it.

```bash
# Step 1: See all symbols defined in the file
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "$ARGUMENTS"

# Step 2: Find files connected via imports
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "$ARGUMENTS"
```

**When to chain further:** Read the most-connected related files to understand the broader subsystem. Use `find-usages` on key exported symbols to see where they're consumed.

## Mode: trace

Trace the usage chain of a symbol across the codebase — who calls it, who imports it, and how it flows.

```bash
# Step 1: Find all files that import the symbol
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-usages "$ARGUMENTS"

# Step 2: For each importing file, check what it does with it
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "<importing-file>"

# Step 3: Follow the chain — check related files of heavy consumers
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<importing-file>"
```

**When to chain further:** If the symbol is re-exported or wrapped, trace the wrapper's usages too. Stop when you reach the user-facing entry point (route handler, CLI command, UI component).

## Mode: navigate

Free-form query-driven search when you're not sure what you're looking for. Searches across symbol names, file paths, and import graphs.

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js navigate "$ARGUMENTS"
```

**When to chain further:** Use the results to identify relevant files, then switch to `explore` or `find` mode for deeper investigation.

## Chaining Patterns

Common multi-step navigation sequences:

**Architecture understanding:**
1. `map` → identify key directories
2. `file-overview` on entry points → see exports
3. `related-files` on core modules → see dependency graph

**Bug investigation:**
1. `find-symbol` on the error source → locate the function
2. `file-overview` on that file → see surrounding context
3. `find-usages` on the function → see all call sites
4. Read each call site to find the bug trigger

**Dependency impact analysis:**
1. `find-usages` on the symbol being changed → see all consumers
2. `related-files` on each consumer → see secondary effects
3. Report the full blast radius before making changes

## Context Awareness

Before running commands:
- Check if the project has already been indexed this session (the `session-index.sh` hook auto-indexes at session start)
- If files were recently edited, run `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js index-file "<path>"` to incrementally re-index changed files
- Skip re-reading files already loaded in context — check the conversation for prior file reads before using Read

## Reindex

If the index seems stale (symbols not found that should exist, or recently added files missing):

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js index
```

This rebuilds the full index. Use `index-file <path>` for incremental updates after single-file edits.
