---
title: CLI Reference
parent: Codebase Pilot
grand_parent: Reference
nav_order: 1
---

# CLI Reference

All commands use the codebase-pilot CLI:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js <command>
```

The `CODEBASE_PILOT_PROJECT_ROOT` environment variable sets the project root. Defaults to the current directory.

## Commands

### index

```bash
codebase-pilot index [path]
```

Full project indexing. Discovers all source files, parses with tree-sitter, builds SQLite database at `.codeindex/db.sqlite`. Skips unchanged files on subsequent runs.

### index-file

```bash
codebase-pilot index-file <path>
```

Incremental single-file reindex. Used by the `reindex-on-edit.sh` hook after file edits.

### map

```bash
codebase-pilot map [path]
```

Project overview: file count, language breakdown, directory tree (2 levels), entry points, top exported symbols.

### find-symbol

```bash
codebase-pilot find-symbol <name> [--kind <kind>]
```

FTS5 prefix search for symbols by name. Optional `--kind` filter: function, class, interface, type, enum, variable, method, property. Returns up to 30 results with signatures and file locations.

### find-usages

```bash
codebase-pilot find-usages <name>
```

Find all files that import a symbol. Returns file paths with imported symbol names. Up to 50 results.

### file-overview

```bash
codebase-pilot file-overview <path>
```

List all symbols and imports in a file. Grouped by kind with signatures. Includes context tags showing if the file is already in your session context.

### related-files

```bash
codebase-pilot related-files <path>
```

Two-way import graph: files this file imports from, and files that import from this file.

### navigate

```bash
codebase-pilot navigate <query>
```

Multi-channel search with scoring. Searches symbols (FTS5), file paths, and import sources. Results ranked by relevance with context bonuses for files already in your session.

### dead-code

```bash
codebase-pilot dead-code
```

Find exported symbols that are never imported anywhere in the project.

### change-impact

```bash
codebase-pilot change-impact <symbol>
```

Show all files that would be affected if a symbol's definition changes. Separates direct importers from test files.

### context-budget

```bash
codebase-pilot context-budget
```

Rank import sources by frequency. Most-imported files listed first — these are the files you should understand first.

### api-surface

```bash
codebase-pilot api-surface
```

List all exported symbols across the project, grouped by file.

### circular-deps

```bash
codebase-pilot circular-deps
```

Detect circular import chains via DFS graph traversal. Returns up to 20 cycles.

### doctor

```bash
codebase-pilot doctor
```

Health check: verifies SQLite, tree-sitter grammars (native + WASM), index existence, and freshness.
