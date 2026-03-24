---
title: "Coordinate Agents"
description: "Coordinate Agents — claudetools documentation."
---
Use the agent mesh to coordinate multiple Claude agents working in the same repository simultaneously — checking who is active, locking files, sending messages, and sharing architectural decisions.


## What you need
- claudetools installed
- A git repository with worktree isolation enabled (each agent works in its own worktree)

## Steps

### 1. Check who is active

Before starting work on shared files, see who else is in the repo:

```
/mesh status
```

This runs three commands:

```bash
# List active agents
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js list --brief

# Show active file locks
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js locks

# Show shared decisions
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --list
```

Run this at the start of every session and before starting work on any shared code.

### 2. Lock a file before a multi-file refactor

Advisory locks prevent two agents from editing the same file simultaneously:

```
/mesh lock src/api/auth.ts "mid-migration to new session format"
```

This runs:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js lock \
  --file "src/api/auth.ts" \
  --id "$SESSION_ID" \
  --reason "mid-migration to new session format"
```

Check who holds a lock before editing:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js who --file "src/api/auth.ts"
```

Release the lock when done:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js unlock --file "src/api/auth.ts" --id "$SESSION_ID"
```

### 3. Send a message to another agent

Alert another agent before touching files they depend on:

```
/mesh send researcher "don't touch config.ts — I'm mid-migration on the auth module"
```

Message types:
- `info` — general update ("finished refactoring the auth module")
- `alert` — something they need to know now ("don't touch config.ts")
- `request` — asking for something ("can you review my API layer changes?")
- `decision` — sharing an architectural choice ("going with JWT, not sessions")

### 4. Share an architectural decision

When you make a choice that affects the whole codebase, store it in the shared context:

```
/mesh decide auth-strategy "JWT with 15-minute access tokens and 7-day refresh tokens"
```

This runs:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context \
  --set "auth-strategy" \
  "JWT with 15-minute access tokens and 7-day refresh tokens"
```

Other agents can read the decision:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --get "auth-strategy"
```

### 5. Spawn a team with TeamCreate

For work with 3+ independent tasks, use TeamCreate to run them in parallel:

```
/managing-tasks start
```

The task system calls TeamCreate internally, spawning one teammate per independent subtask. Each teammate gets scoped context — their task content, relevant file paths, and constraints — rather than the full conversation history.

For a custom team, Claude can create one directly:

```
spawn three teammates:
- researcher: explore the auth module
- implementer: add the JWT refresh endpoint
- reviewer: review the implementer's output
```

### 6. Maintain worktree isolation

Each agent session should run in its own git worktree. Create a worktree for a new session:

```bash
git worktree add .claude/worktrees/my-feature -b my-feature
```

Agents working in separate worktrees can edit different files simultaneously without conflicts. The agent mesh coordinates at a higher level — file locks are advisory and cross-worktree communication happens via the mesh CLI, not git.

## What happens behind the scenes

- The **agent-mesh CLI** (`plugin/agent-mesh/cli.js`) stores state in a local JSON file shared across worktrees — no network required
- **Locks are advisory** — they do not prevent editing, they signal intent. Agents must check locks before starting work
- **Context store** persists for the session — decisions written by one agent are immediately readable by others
- **Inbox** is checked automatically by hooks when messages arrive — you can also check manually: `node .../cli.js inbox --id $SESSION_ID`
- **TeamCreate** isolates each teammate's context window from the main conversation, keeping it clean and preventing context overflow

## Tips

- Always check `/mesh status` before starting work in a shared repo — five seconds now prevents a merge conflict later
- Lock files when doing multi-file refactors, not for single-line fixes — over-locking creates coordination overhead
- Use `decision` message type for architectural choices so they appear in the shared context list, not just as one-off messages
- If the mesh CLI is unavailable (e.g. not yet installed), mesh commands are best-effort — report the issue and continue working
- Commit agent coordination notes to `.tasks/progress.md` via `/managing-tasks handoff` so the next session has full context

## Related

- [Manage Tasks](manage-tasks.md) — task system coordinates with TeamCreate
- [Build a Feature](build-a-feature.md) — feature-pipeline uses the mesh for multi-teammate implementation
- [Set Up a New Project](setup-new-project.md) — worktree setup for new projects
