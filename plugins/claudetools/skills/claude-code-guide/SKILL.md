---
name: claude-code-guide
description: >
  Best practices reference for building Claude Code extensions — skills, hooks,
  agents, plugins, slash commands, scripts, MCP servers, CLAUDE.md, memory, and
  task systems. Use when creating, modifying, or troubleshooting any Claude Code
  extension component.
argument-hint: "[topic or question about Claude Code extensions]"
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: development
  tags: [claude-code, plugins, hooks, skills, mcp, reference]
---

# Claude Code Extension Guide

A curated reference for building reliable Claude Code extensions. Routes to the
right guide based on what you are building.

## When to Use

Use this skill when:
- Creating or configuring Claude Code plugins, hooks, skills, or MCP servers
- Writing or testing agent definitions
- Troubleshooting hook behavior or skill loading
- Understanding CLAUDE.md patterns or memory system integration

## Quick Reference

| Building... | Read this reference |
|---|---|
| A skill | `${CLAUDE_SKILL_DIR}/references/skills-guide.md` |
| A hook | `${CLAUDE_SKILL_DIR}/references/hooks-guide.md` |
| An agent | `${CLAUDE_SKILL_DIR}/references/agents-guide.md` |
| Prompts or instructions | `${CLAUDE_SKILL_DIR}/references/prompting-guide.md` |
| CLAUDE.md project instructions | `${CLAUDE_SKILL_DIR}/references/claude-md-guide.md` |
| An MCP server | `${CLAUDE_SKILL_DIR}/references/mcp-servers-guide.md` |
| A plugin | `${CLAUDE_SKILL_DIR}/references/plugins-guide.md` |
| Memory or task integration | `${CLAUDE_SKILL_DIR}/references/memory-task-guide.md` |

## Validation

Run the appropriate validator to check your work:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/validate-skill.sh /path/to/skill-directory
bash ${CLAUDE_SKILL_DIR}/scripts/validate-hook.sh /path/to/hook-script.sh
bash ${CLAUDE_SKILL_DIR}/scripts/validate-agent.sh /path/to/agent.md
bash ${CLAUDE_SKILL_DIR}/scripts/validate-plugin.sh /path/to/plugin-directory
bash ${CLAUDE_SKILL_DIR}/scripts/validate-mcp.sh /path/to/mcp-server-directory
```
