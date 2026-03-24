---
title: "/memory"
description: "Manage persistent cross-session developer memory — add, search, decay, prune, and sync memory entries to CLAUDE.md."
---

> **Status:** 🆕 New in v4.0 — migrated to native command format in the v4.0.0 release

Manage developer memory — persistent cross-session knowledge injected into every conversation via CLAUDE.md.

## Invocation

```
/memory [subcommand] [args]
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| *(none)* | Status overview: entry count, last generation timestamp, config status |
| `view` | Show all developer-controlled memory entries |
| `show` | Show the full injected memory block (what Claude Code actually sees) |
| `add "<content>"` | Add a new memory entry (auto-converted to third person) |
| `remove <N>` | Remove entry N (shows entry and asks confirmation) |
| `replace <N> "<new>"` | Replace entry N (shows change and asks confirmation) |
| `regenerate` | Force re-generation of the auto-generated memory context |
| `status` | Full diagnostic report of the memory system |
| `reset` | Delete all memory data (preserves config; requires "yes" confirmation) |
| `export` | Export full memory state as a markdown document |

## Natural Language Triggers

| Pattern | Action |
|---------|--------|
| "remember that..." | Treated as `add` |
| "forget about..." | Treated as `remove` |
| "update your memory..." | Treated as `replace` |
| "what do you remember?" | Treated as `view` with summary |

## Quick example

```
/memory view
```

**Claude responds:**

```
Memory entries (6)

  1. Prefers pnpm over npm for package management
  2. Uses TypeScript strict mode in all projects
  3. Runs tests with vitest, not jest
  4. API keys stored in .env.local, never committed
  5. Database migrations use Drizzle ORM
  6. Deploys to Fly.io — uses fly deploy, not Docker directly
```

```
/memory add "Always use kebab-case for branch names"
```

**Claude responds:**

```
Added memory entry:
  7. Always uses kebab-case for branch names

Memory regenerated — CLAUDE.md updated.
```

## Examples

```
/memory
/memory view
/memory add "Prefers pnpm over npm"
/memory remove 3
/memory replace 2 "Uses TypeScript strict mode in all projects"
/memory show
/memory status
/memory export
```

## Notes

- All memory operations go through MCP tools — the command does not read/write files directly (except `show` and `status`).
- Entries are stored in third person: "Prefers tabs over spaces", not "I prefer tabs".
- `reset` never deletes `config.yaml` — only content files.
- The system never draws attention to the memory system in responses unless directly asked.

## Related

- [Core Concepts — Task System](/getting-started/core-concepts/#task-system) — persistent task tracking (complements memory for cross-session state)
- [Reference: context-hooks](/reference/hooks/context-hooks/) — the hooks that inject memory at session start and on each prompt
- [FAQ — Memory system](/getting-started/faq/#daily-usage) — answers about memory injection and how to tune it
