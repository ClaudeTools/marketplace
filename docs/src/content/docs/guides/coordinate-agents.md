---
title: "Coordinate Agents"
description: "Run multiple Claude agents in parallel with file locks, shared decisions, and message passing."
---

**Difficulty: Advanced**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- [Core Concepts](../getting-started/core-concepts.md) — understanding agents and the agent mesh
- [Manage Tasks](manage-tasks.md) — multi-agent sessions use the task system for coordination
- [Build a Feature](build-a-feature.md) — the feature-pipeline is the most common multi-agent workflow
:::


Use the agent mesh to coordinate multiple Claude agents working in the same repository simultaneously — checking who is active, locking files, sharing architectural decisions, and passing messages between sessions.

## Real scenarios

### Scenario A: Spawning a team and dividing work

> "spawn three teammates to refactor the auth module: one to audit the current code, one to write the new JWT implementation, and one to update the tests"

:::note[Behind the scenes]
TeamCreate spawns each agent in an isolated context window with scoped instructions. Each gets only the files and context relevant to their task — not the full conversation history.
:::

The team lead (you) coordinates. The three teammates start independently:

- **auditor** — reads the existing auth code, identifies what's being replaced
- **implementer** — builds the new JWT implementation
- **tester** — waits for the implementer's output, then updates tests

Before the implementer touches shared files, it checks for locks:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js who --file "src/api/auth.ts"
# No lock held
```

Clear — it proceeds and locks the file:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js lock \
  --file "src/api/auth.ts" \
  --id "$SESSION_ID" \
  --reason "rewriting JWT implementation"
```

---

### Scenario B: One agent checks a lock held by another

The tester agent starts and wants to read `src/api/auth.ts` to understand what changed:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js who --file "src/api/auth.ts"
# Lock held by implementer (session abc-123): rewriting JWT implementation
```

:::note[Behind the scenes]
Locks are advisory — the tester can still read the file. The lock signals intent: "this file is in flux, coordinate before editing." The tester reads the file but waits to write tests until the implementer unlocks it.
:::

---

### Scenario C: Sharing an architectural decision across the team

The implementer makes a key choice and records it so all other agents can read it:

> "/mesh decide auth-strategy 'JWT with 15-minute access tokens and 7-day refresh tokens, stored in httpOnly cookies — no localStorage'"

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context \
  --set "auth-strategy" \
  "JWT with 15-minute access tokens and 7-day refresh tokens, stored in httpOnly cookies — no localStorage"
```

The tester reads the decision before writing tests:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --get "auth-strategy"
# JWT with 15-minute access tokens and 7-day refresh tokens, stored in httpOnly cookies — no localStorage
```

Now the tester knows to write tests for httpOnly cookies, not localStorage. No need for the implementer to repeat themselves.

---

### Scenario D: Sending an alert to another agent

The implementer realizes it's changing a shared utility that the auditor was also reading:

> "/mesh send auditor 'heads up — I moved token validation out of auth.ts and into src/lib/tokens.ts, update your audit findings'"

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js send \
  --to "auditor" \
  --message "heads up — I moved token validation out of auth.ts and into src/lib/tokens.ts, update your audit findings" \
  --type "alert"
```

:::note[Behind the scenes]
A PostToolUse hook delivers the message to the auditor's inbox automatically. The auditor does not need to poll — it sees the alert the next time it calls a tool.
:::

The auditor acknowledges:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js inbox --id "$SESSION_ID"
# [alert from implementer] heads up — I moved token validation out of auth.ts and into src/lib/tokens.ts
```

---

### Scenario E: Checking the full team status

> "/mesh status"

```
Active agents (3):
  auditor      [session abc-111]  reading src/api/auth.ts
  implementer  [session abc-123]  locked src/api/auth.ts, src/lib/tokens.ts
  tester       [session abc-456]  waiting on implementer

File locks (2):
  src/api/auth.ts     → implementer (abc-123): rewriting JWT implementation
  src/lib/tokens.ts   → implementer (abc-123): new token validation module

Shared decisions:
  auth-strategy: JWT with 15-minute access tokens...
```

---

:::tip[When to use the mesh vs just asking]
- **No coordination needed**: Single agent, single task — just ask Claude directly
- **Parallel independent tasks**: Spawn teammates with TeamCreate, no mesh needed
- **Parallel tasks touching shared files**: Lock files before editing, `/mesh decide` for architectural choices
- **Long-running multi-session work**: Use `/mesh status` at the start of every session and `/task-manager handoff` before ending
:::

## What happens behind the scenes

- The **agent-mesh CLI** (`plugin/agent-mesh/cli.js`) stores state in a local JSON file shared across worktrees — no network required
- **Locks are advisory** — they signal intent, not access control. Agents must check locks before starting work, not before reading
- **Context store** persists for the session — decisions written by one agent are immediately readable by others in the same session
- **Inbox** delivery is triggered automatically by a PostToolUse hook — agents receive messages without polling
- **TeamCreate** isolates each teammate's context window from the main conversation, keeping it clean and preventing context overflow

## Tips

- Run `/mesh status` at the start of every multi-agent session — five seconds now prevents a merge conflict later
- Lock files for multi-file refactors, not single-line fixes — over-locking creates coordination overhead without benefit
- Use the `decision` context store for architectural choices so they appear in `/mesh status`, not buried in one-off messages
- Commit `.tasks/progress.md` via `/task-manager handoff` before ending a multi-agent session — the next session needs full context, not just git history

## Related

- [Manage Tasks](manage-tasks.md) — task system coordinates with TeamCreate for parallel execution
- [Build a Feature](build-a-feature.md) — feature-pipeline uses the mesh for multi-teammate implementation
- [Set Up a New Project](setup-new-project.md) — worktree setup for isolated agent sessions
