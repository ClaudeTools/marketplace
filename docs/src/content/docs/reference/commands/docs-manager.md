---
title: "/docs-manager"
description: "Documentation management command — audit, archive, generate index, and enforce standardized structure across project docs."
---

> **Status:** 🆕 New in v4.0 — migrated to native command format in the v4.0.0 release

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

## Quick example

```
/docs-manager audit
```

**Claude responds:**

```
docs/ audit — 3 issues found

  docs/api/authentication.md
    ✗ Missing front matter (no title or description)

  docs/guides/setup.md
    ✗ Stale date: last_updated 2023-04-12 (over 12 months ago)

  docs/reference/webhooks.md
    ✗ Generic title: "Webhooks" — consider a more descriptive title

  docs/index.md                 ✓
  docs/guides/quickstart.md     ✓
  docs/api/endpoints.md         ✓
  ... (14 more files, all passing)

Run /docs-manager reindex to regenerate index files.
```

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

## Related

- [Advanced: Architecture](/advanced/architecture/) — the hook that enforces doc standards on every file write
- [Reference: /logs command](logs.md) — check session history when investigating doc-related tool failures
- [Reference: plugin-improver skill](/reference/skills/plugin-improver/) — improvement loop that uses docs-manager audit data
