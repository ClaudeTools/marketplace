---
title: "/claude-code-guide"
description: "/claude-code-guide — claudetools documentation."
---
Best practices reference for building Claude Code extensions — skills, hooks, agents, plugins, slash commands, scripts, MCP servers, CLAUDE.md, memory, and task systems.

## Invocation

```
/claude-code-guide [what-you-are-building]
```

**Arguments:** One of: `skill`, `hook`, `agent`, `plugin`, `script`, `mcp-server`, `claude-md`, `memory`, `prompts`

## Routing

The command reads `$ARGUMENTS` to load only the relevant reference file. Only one reference is loaded per invocation.

| Building... | Reference Loaded |
|-------------|-----------------|
| `skill` | `skills-guide.md` |
| `hook` | `hooks-guide.md` |
| `agent` | `agents-guide.md` |
| `prompts` | `prompting-guide.md` |
| `claude-md` | `claude-md-guide.md` |
| `mcp-server` | `mcp-servers-guide.md` |
| `plugin` | `plugins-guide.md` |
| `memory` or `task` | `memory-task-guide.md` |

If the intent spans multiple types, both relevant references are loaded.

## Universal Principles

Loaded for all invocations (not included in referenced files):
- Deterministic tooling over AI inference — if a shell command can do it, use it
- Verify before claiming done — run the checker, don't trust "looks correct"
- No stubs or placeholders — implement fully or say you can't

## Examples

```
/claude-code-guide skill
/claude-code-guide hook
/claude-code-guide mcp-server
/claude-code-guide plugin
```
