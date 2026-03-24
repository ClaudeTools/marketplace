---
title: "Exploring Codebase"
description: "Skill that wraps codebase-pilot CLI into workflow modes — symbol search, import tracing, architecture mapping, and dependency analysis."
---
Structured codebase navigation using the codebase-pilot CLI. Wraps CLI commands into workflow modes that chain for deeper understanding.

**Trigger:** Use when the user asks to understand unfamiliar code, find where something is defined, trace what calls a function, explore how a module works, or get a project overview.

**Invocation:** `/exploring-codebase [query or file path]`

---

## When to use this

Use this skill any time you're working in a codebase you don't fully know — whether that's day one on a new project or tracking down where an obscure function is defined. It's also useful mid-task when you need to trace what a change will affect before making it. Rather than reading files one by one and hoping you find the right one, this skill uses the semantic index to answer structural questions directly.

---

## Try it now

```
/exploring-codebase How does this project handle authentication?
```

Claude will use codebase-pilot to map the project, find auth-related symbols, trace their import chains, and return a structured summary covering entry points, middleware, token flow, and key files — without reading every file blindly.

---

## Mode Selection

| User Intent | Mode | Commands Used |
|-------------|------|---------------|
| "How is this project structured?" | **map** | `map` |
| "Where is X defined?" | **find** | `find-symbol`, then `file-overview` on result |
| "How does this file/module work?" | **explore** | `file-overview` + `related-files` |
| "What uses X?" / "Trace dependency chain" | **trace** | `find-usages` + `related-files` on each result |
| "Where does field get transformed?" | **trace-field** | `trace-field.sh` script |
| "Which handler serves this route?" | **find-route** | `find-route.sh` script |
| "Find all queries on table" | **find-queries** | `find-queries.sh` script |

---

## Workflow Steps

1. Determine the mode from the user's intent using the table above.
2. Run codebase-pilot CLI commands for that mode.
3. Skip re-reading files already marked `[in context]` in CLI output.
4. Build a structured summary: architecture, data flow, entry points, key dependencies.
5. Read only files the CLI confirms are relevant — never guess file paths.

---

## CLI Reference

CLI path: `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js`

| Command | Purpose |
|---------|---------|
| `map` | Project overview: languages, structure, entry points, key exports |
| `find-symbol "<name>"` | Find functions, classes, types by name |
| `find-usages "<name>"` | Find all files that import a symbol |
| `file-overview "<path>"` | List all symbols in a file, grouped by kind |
| `related-files "<path>"` | Find files connected via imports (both directions) |
| `navigate "<query>"` | Query-driven search across symbols, paths, imports |

---

## Example Invocations

```
/exploring-codebase How does this project handle authentication?
/exploring-codebase Where is validatePayment defined?
/exploring-codebase What imports the UserRepository?
/exploring-codebase src/api/billing.ts
```

---

## Related Components

- **codebase-pilot CLI** — the underlying tool this skill wraps (see [CLI Reference](../codebase-pilot/cli-reference.md))
- **codebase-navigation rule** — full command reference table injected when editing code files
- **investigating-bugs skill** — uses the same CLI for evidence gathering in debug workflows
