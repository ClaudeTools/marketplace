---
title: "/docs-manager"
description: "/docs-manager — claudetools documentation."
---
Manage project documentation with standardized structure, auditing, archiving, and index generation.

## Invocation

```
/docs-manager [command]
```

Default command (no argument): `audit`

## Commands

| Command | Purpose |
|---------|---------|
| `init` | Create a standard `docs/` directory structure with front-matter templates |
| `audit` | Scan all `docs/` directories for quality issues |
| `archive` | Move deprecated docs to `docs/archive/` and update indexes |
| `reindex` | Force-regenerate `index.md` files for all `docs/` directories |

## Audit Checks

The `audit` command scans for:
- Missing front matter
- Stale dates
- Naming convention violations
- Generic or missing titles
- Empty files

## Examples

```
/docs-manager
/docs-manager audit
/docs-manager init
/docs-manager archive
/docs-manager reindex
```

## Notes

- The `archive` command moves documents with `status: deprecated` in their front matter.
- `reindex` is useful after adding or removing many documentation files.
- Run `audit` regularly as part of documentation maintenance.
