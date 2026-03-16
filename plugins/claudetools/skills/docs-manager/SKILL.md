---
name: docs-manager
description: Manage project documentation with standardized structure, auditing, archiving, and index generation. Use when the user says docs init, docs audit, docs archive, docs reindex, manage docs, or documentation setup.
argument-hint: <command> [init|audit|archive|reindex]
allowed-tools: Read, Bash, Grep, Glob, Write, Edit
context: fork
agent: general-purpose
metadata:
  author: Owen Innes
  version: 1.0.0
  category: documentation
  tags: [docs, documentation, audit, archive, index]
---

# Documentation Manager

Manage project documentation with standardized structure and quality checks.

## Commands

### init
Create a standard docs/ directory structure with front-matter templates.
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-init.sh
```

### audit
Scan all docs/ directories for quality issues: missing front matter, stale dates, naming violations, generic titles, empty files.
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-audit.sh
```

### archive
Find docs with `status: deprecated` in front matter, move them to docs/archive/, and update indexes.
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh
```

### reindex
Force-regenerate index.md files for all docs/ directories.
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-reindex.sh
```

## Workflow

1. Parse the command from `${ARGUMENTS}` (default to `audit` if no command given).
2. Run the corresponding script above.
3. Present the output to the user.
