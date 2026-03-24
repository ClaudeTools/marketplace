---
title: "Indexing"
description: "How codebase-pilot indexes your project — when indexing runs, what triggers reindexing, and how to inspect or reset the index."
---
## When indexing happens

| Trigger | What happens |
|---------|-------------|
| **Session start** | `session-index.sh` hook runs `codebase-pilot index` if the database is stale or missing |
| **File edit** | `reindex-on-edit.sh` hook runs `codebase-pilot index-file <path>` on the changed file |
| **Config change** | `session-index.sh` fires again on ConfigChange events |
| **Worktree create** | `session-index.sh` fires to index the new worktree |
| **Manual** | Run `codebase-pilot index` via Bash |

## Database location

The index is stored at `.codeindex/db.sqlite` in your project root. It uses SQLite with WAL mode and FTS5 for full-text search.

## What gets indexed

- All source files matching supported language extensions
- Skips: `node_modules`, `.git`, `dist`, `build`, `.next`, `coverage`, `.turbo`, `.cache`, `__pycache__`, `.venv`, `vendor`, `target`
- Maximum: 10,000 source files (guard against memory exhaustion)

## Incremental updates

On subsequent runs, `index` checks `modified_at` timestamps against the filesystem. Only changed files are re-parsed. Deleted files are removed from the database.

## Schema

| Table | Purpose |
|-------|---------|
| `files` | All indexed files with path, language, size, modified timestamp |
| `symbols` | Functions, classes, types with name, kind, line range, signature, export status, parent reference |
| `symbols_fts` | FTS5 virtual table for fast prefix search on symbol names and signatures |
| `imports` | Import relationships: which file imports what from where |
| `meta` | Schema version tracking |

## Troubleshooting

Run `codebase-pilot doctor` to diagnose issues:
- SQLite loads correctly
- Tree-sitter grammars available
- Index exists and contains files
- Index is fresh (not stale)

---

## Related

- [CLI Reference](cli-reference.md) — all codebase-pilot commands and flags
- [Supported Languages](supported-languages.md) — which file types get indexed
- [Reference: Context Hooks](/reference/hooks/context-hooks/#reindex-on-edit) — the hook that triggers incremental reindexing after edits
