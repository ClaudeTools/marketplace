---
title: "/mesh"
description: "Multi-agent coordination command — check active agents, lock files, send messages, and share architectural decisions across worktrees."
---
Coordinate with other Claude agents working in the same repository. Check agent status, send messages, lock files, and share architectural decisions.

## Invocation

```
/mesh [subcommand] [args]
```

Default subcommand (no argument): `status`

## Subcommands

### `status`
Show who is working in this repo and what they're doing.

```bash
node .../agent-mesh/cli.js list --brief
node .../agent-mesh/cli.js locks
node .../agent-mesh/cli.js context --list
```

**When to use:** At session start, before touching shared code, or when you suspect conflicts.

### `send <agent-name> <message>`
Send a message to another agent.

Message types (via `--type`):
- `info` — general updates
- `alert` — something the other agent needs to know now
- `request` — asking for something
- `decision` — sharing an architectural choice

**When to use:** When your work affects another agent's files, when you finish a task others depend on, or when you discover something another agent should know.

### `lock <file-path> [reason]`
Acquire an advisory lock on a file before multi-file changes. Use `who <path>` to check who's currently working on a file.

**When to use:** Before refactoring that touches multiple files or modifying shared config.

### `decide <key> <value>`
Store an architectural decision in the shared context store. Use `context --list` to see all shared decisions.

**When to use:** After making an architectural choice that affects the whole codebase.

## Quick example

```
/mesh status
```

**Claude responds:**

```
Agent Mesh — 2 agents active

  frontend-agent  (worktree: feature/redesign)
    Status:  active
    Locks:   src/components/Nav.tsx, src/styles/tokens.css
    Last seen: 4 min ago

  backend-agent  (worktree: feature/auth-rewrite)
    Status:  idle
    Locks:   src/middleware/auth.ts
    Last seen: 12 min ago

Shared decisions:
  auth-strategy  →  "session-based, not JWT"
  db-client      →  "use existing PrismaClient singleton"
```

```
/mesh send frontend-agent "Heads up — I'm updating the auth token shape, NavBar may need changes"
```

**Claude responds:**

```
Message sent to frontend-agent.
```

## Examples

```
/mesh
/mesh status
/mesh send backend-agent "Don't touch auth.ts — I'm mid-migration"
/mesh lock src/config/database.ts "Migrating connection pool settings"
/mesh decide auth-strategy "session-based, not JWT"
```

## Notes

- All mesh commands are best-effort. If the CLI is unavailable, report the issue but continue with the task.
- The underlying CLI is at `plugin/agent-mesh/cli.js` (see [Agent Mesh](../agent-mesh.md)).
- Locks are advisory — the system does not prevent simultaneous edits, but hooks warn when a locked file is edited.
