---
name: docs-manager
description: >
  Manage project documentation with standardized structure, auditing, archiving,
  and index generation. Use when asked to organize docs, check for stale
  documentation, generate a docs index, or set up a docs directory.
argument-hint: "[audit|reindex|archive|init]"
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: documentation
  tags: [docs, documentation, index, audit, archive]
---

# Documentation Manager

Standardized documentation workflows for project docs directories.

## Commands

| Command | Script | Purpose |
|---------|--------|---------|
| `init` | `${CLAUDE_SKILL_DIR}/scripts/docs-init.sh` | Set up docs/ directory structure |
| `audit` | `${CLAUDE_SKILL_DIR}/scripts/docs-audit.sh` | Check for stale, orphaned, or missing docs |
| `reindex` | Handled automatically at session end by `validators/doc-index.sh` | Regenerate docs/index.md from frontmatter |
| `archive` | `${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh` | Move outdated docs to docs/archive/ |
