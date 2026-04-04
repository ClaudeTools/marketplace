---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.rs"
  - "**/*.go"
  - "**/*.java"
  - "**/*.rb"
---

# Codebase Navigation — CLI Commands

Use the srcpilot CLI to navigate code precisely before reading files directly.

**CLI path:** `srcpilot <command>`

## Commands

| Command | Usage | Purpose |
|---------|-------|---------|
| `map` | `srcpilot map` | Project overview: languages, structure, entry points, key exports |
| `find` | `srcpilot find "<name>"` | Find functions, classes, types by name (supports prefix matching) |
| `usages` | `srcpilot usages "<name>"` | Find all files that import a given symbol |
| `overview` | `srcpilot overview "<path>"` | List all symbols in a file, grouped by kind |
| `related` | `srcpilot related "<path>"` | Find files connected via imports (both directions) |
| `navigate` | `srcpilot navigate "<query>"` | Query-driven search across symbols, paths, and imports — ranked results |
| `why` | `srcpilot why "<query>"` | Rank root nodes and likely owners for a concept |
| `next` | `srcpilot next "<query>"` | Rank what to open next (import frequency + centrality) |
| `ambiguities` | `srcpilot ambiguities` | Find duplicate symbol names and split ownership |
| `budget` | `srcpilot budget` | Rank files by import frequency (core context budget) |
| `exports` | `srcpilot exports` | List all exported symbols (API surface) |
| `cycles` | `srcpilot cycles` | Detect circular imports |
| `implementations` | `srcpilot implementations "<symbol>"` | Find competing implementations of a symbol |

## Context Awareness

Files marked `[in context]` are already in your context window — do NOT re-read them. This saves tokens and avoids redundant work. The tag appears automatically in `find`, `overview`, `related`, and `navigate` output.

## When to Use Which Command

- Use `find` when you know the exact function/class/type name
- Use `navigate` when you have a general idea (e.g., "session read tracking", "auth middleware")
- Use `overview` to understand a file's structure before reading it
- Use `related` to find connected files via imports
- Use `why` when you need to understand architectural ownership or trace root causes
- Use `next` when navigating an unfamiliar area and unsure what to read after current file
- Use `budget` to prioritize which files to load into context for a large task
- Use `cycles` before a refactor involving module splits
- Use `ambiguities` when renaming to check for name conflicts first

## Required Behavior

ALWAYS use srcpilot CLI to locate code before reading files directly.

**WRONG:** Reading random files hoping to find the right code:
```bash
Read plugin/scripts/validators/ai-safety.sh  # guessing the file path
```

**CORRECT:** Using the CLI to locate code precisely:
```bash
srcpilot find "validate_ai_safety"
```

Then read the exact file and line reported by the CLI.
