---
title: Codebase Pilot
parent: Reference
nav_order: 6
has_children: true
---

# Codebase Pilot

Tree-sitter + SQLite indexing engine for semantic code navigation. Parses your codebase into a queryable database of symbols, imports, and file relationships.

## Quick start

Codebase Pilot indexes your project automatically at session start. Use the CLI to query it:

```bash
codebase-pilot map                        # Project overview
codebase-pilot find-symbol "handleAuth"   # Find any function, class, or type
codebase-pilot change-impact "handleAuth" # What breaks if this changes?
codebase-pilot dead-code                  # Find unused exports
```

See [CLI Reference](/reference/codebase-pilot/cli-reference/) for all 14 commands.
