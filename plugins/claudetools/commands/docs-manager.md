---
description: Manage project documentation with standardized structure, auditing, and archiving.
argument-hint: "<command> [init|audit|archive]"
---

# Documentation Manager

Manage project documentation with standardized structure and quality checks.

## Commands

### init
Create a standard docs/ directory structure with front-matter templates.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-init.sh
```

### audit
Scan all docs/ directories for quality issues: missing front matter, stale dates, naming violations, generic titles, empty files.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-audit.sh
```

### archive
Find docs with `status: deprecated` in front matter, move them to docs/archive/, and update indexes.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-archive.sh
```

## Workflow

1. Parse the command from `$ARGUMENTS` (default to `audit` if no command given).
2. Run the corresponding script above.
3. Present the output to the user.
