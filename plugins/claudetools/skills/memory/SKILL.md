---
name: memory
description: >
  Manage developer memory — persistent cross-session knowledge. Query, update,
  and maintain the episodic memory system.
argument-hint: "[search|update|consolidate]"
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: internal
  tags: [memory, episodic, cross-session, internal]
---

# Memory Management

Manage the persistent cross-session memory system.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `${CLAUDE_SKILL_DIR}/scripts/memory-search.py` | Search memory entries |
| `${CLAUDE_SKILL_DIR}/scripts/memory-update.py` | Update or create memory entries |
