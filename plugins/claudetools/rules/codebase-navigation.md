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
| `find-symbol` | `srcpilot find-symbol "<name>"` | Find functions, classes, types by name (supports prefix matching) |
| `find-usages` | `srcpilot find-usages "<name>"` | Find all files that import a given symbol |
| `file-overview` | `srcpilot file-overview "<path>"` | List all symbols in a file, grouped by kind |
| `related-files` | `srcpilot related-files "<path>"` | Find files connected via imports (both directions) |
| `navigate` | `srcpilot navigate "<query>"` | Query-driven search across symbols, paths, and imports — ranked results |

## Context Awareness

Files marked `[in context]` are already in your context window — do NOT re-read them. This saves tokens and avoids redundant work. The tag appears automatically in `find-symbol`, `file-overview`, `related-files`, and `navigate` output.

## When to Use Which Command

- Use `find-symbol` when you know the exact function/class/type name
- Use `navigate` when you have a general idea (e.g., "session read tracking", "auth middleware")
- Use `file-overview` to understand a file's structure before reading it
- Use `related-files` to find connected files via imports

## Required Behavior

ALWAYS use srcpilot CLI to locate code before reading files directly.

**WRONG:** Reading random files hoping to find the right code:
```bash
Read plugin/scripts/validators/ai-safety.sh  # guessing the file path
```

**CORRECT:** Using the CLI to locate code precisely:
```bash
srcpilot find-symbol "validate_ai_safety"
```

Then read the exact file and line reported by the CLI.
