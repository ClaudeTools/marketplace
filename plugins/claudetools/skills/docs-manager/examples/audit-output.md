# Example Audit Output

```
=== Documentation Audit ===
Scanned: 12 files
Errors: 3 | Warnings: 5 | Info: 6

docs/guides/setup.md:
  ERROR: Missing YAML front matter

docs/reference/API Reference.md:
  INFO: Filename 'API Reference.md' is not kebab-case
  INFO: Missing 'type' — add type: guide|reference|decision|tutorial|overview|changelog|api|runbook
  INFO: Missing 'tags' — add tags: [keyword1, keyword2] for categorization

docs/decisions/auth-approach.md:
  WARNING: Last updated 142 days ago (2025-11-18) — threshold is 90 days
  INFO: Missing 'author' — add author: name for maintenance tracking

docs/guides/deployment.md:
  ERROR: Missing 'title' in front matter
  ERROR: Missing 'description' in front matter
  WARNING: Missing 'updated' date — add updated: YYYY-MM-DD
  INFO: Missing 'status' — add status: draft|active|review|deprecated

docs/reference/config.md:
  WARNING: Title 'Document' is generic — use a descriptive title
  WARNING: Description is too short (5 chars) — aim for a meaningful one-line summary
  WARNING: Invalid status 'wip' — use one of: draft active review deprecated

docs/guides/testing.md:
  INFO: Missing 'type' — add type: guide|reference|decision|tutorial|overview|changelog|api|runbook
  INFO: Missing 'tags' — add tags: [keyword1, keyword2] for categorization

---
Required fields: title, description, updated
Recommended fields: status, author, type, tags
See /docs-manager audit for interactive fixes.
```
