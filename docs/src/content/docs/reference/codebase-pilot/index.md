---
title: "Codebase Pilot"
description: "Tree-sitter + SQLite semantic indexing engine for code navigation."
---

Codebase Pilot is a tree-sitter + SQLite indexing engine that powers semantic code navigation across 14 languages. It parses your codebase into a queryable database of symbols, imports, and file relationships.

## Quick start

Codebase Pilot indexes your project automatically at session start. Query it with:

```bash
codebase-pilot map                        # Project overview
codebase-pilot find-symbol "handleAuth"   # Find any function, class, or type
codebase-pilot change-impact "handleAuth" # What breaks if this changes?
codebase-pilot dead-code                  # Find unused exports
```

## Learn more

- [CLI Reference](/marketplace/reference/codebase-pilot/cli-reference/) — all 14 commands with syntax
- [Supported Languages](/marketplace/reference/codebase-pilot/supported-languages/) — 14 languages, native vs WASM
- [Indexing](/marketplace/reference/codebase-pilot/indexing/) — how and when indexing happens
