---
name: mesh
description: Coordinate with other Claude agents working in the same repo. Check status, send messages, lock files, share decisions. Use when multi-agent coordination is needed — e.g., before refactoring shared files, after discovering blocking issues, or to share architectural decisions.
argument-hint: <status|send|lock|decide> [args]
allowed-tools: Bash, Read
metadata:
  author: Owen Innes
  version: 1.0.0
  category: coordination
  tags: [multi-agent, coordination, mesh, worktree]
---

# Agent Mesh Coordination

Coordinate with other Claude agents working in the same repository. Parse the subcommand from the user's argument to determine what to do.

## Subcommands

### `status` (default if no argument)
Show who else is working in this repo and what they're doing.

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js list --brief
```

Also check for any active locks:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js locks
```

And show shared context:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --list
```

**When to use:** At the start of a session, before starting work on shared code, or when you suspect conflicts.

### `send <agent-name> <message>`
Send a message to another agent. Parse the agent name and message from the arguments.

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js send --to "<agent-name>" --message "<text>" --from "${AGENT_MESH_NAME:-agent-$$}"
```

Message types (use `--type`):
- `info` — general updates ("finished refactoring auth module")
- `alert` — something the other agent needs to know now ("don't touch config.ts, I'm mid-migration")
- `request` — asking for something ("can you review my changes to the API layer?")
- `decision` — sharing an architectural choice ("going with session-based auth, not JWT")

**When to use:** When your work affects another agent's files, when you finish a task others depend on, or when you discover something another agent should know.

### `lock <file-path> [reason]`
Acquire an advisory lock on a file before multi-file changes.

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js lock --file "<path>" --id "$SESSION_ID" --reason "<reason>"
```

To release:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js unlock --file "<path>" --id "$SESSION_ID"
```

To check who's working on a file:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js who --file "<path>"
```

**When to use:** Before refactoring that touches multiple files, before modifying shared config files, or when editing files that other agents are likely to touch.

### `decide <key> <value>`
Share an architectural decision or context via the shared context store.

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --set "<key>" "<value>"
```

To read a decision:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --get "<key>"
```

To list all shared decisions:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --list
```

**When to use:** After making an architectural choice that affects the whole codebase (auth strategy, database schema, API design), or to share knowledge that other agents need ("the CI is broken because of X").

## Error Handling

All mesh commands are best-effort. If the CLI is not available or fails, report the issue but continue with the user's task. Coordination is helpful but never blocking.
