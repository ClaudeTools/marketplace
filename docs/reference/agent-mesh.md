---
title: Agent Mesh
parent: Reference
nav_order: 7
---

# Agent Mesh

Cross-session agent coordination system. Enables multiple Claude agents working in the same repository to discover each other, send messages, lock files, and share architectural decisions — preventing conflicts and redundant work.

**CLI:** `node plugin/agent-mesh/cli.js <command>`
**Storage:** `.claude/mesh/` (relative to repo root, shared across worktrees)

---

## Architecture

The mesh stores state in three directories under `.claude/mesh/`:

| Directory | Contents |
|-----------|---------|
| `agents/` | One JSON file per active agent (`{id}.json`) |
| `inbox/` | Per-agent message queues + broadcast queue |
| `locks/` | Advisory file locks (`{hash}.json`) |
| `context/` | Shared key-value context (`shared.jsonl`) |

All writes use atomic rename to prevent corruption from concurrent access.

---

## Commands

### register
```bash
node cli.js register --id ID --name NAME --worktree PATH --branch BRANCH --pid PID [--task TEXT]
```
Register an agent session. Called automatically by `mesh-lifecycle.sh` on SessionStart.

### deregister
```bash
node cli.js deregister --id ID
```
Remove an agent registration. Called on SessionEnd and SubagentStop.

### heartbeat
```bash
node cli.js heartbeat --id ID
```
Update agent heartbeat timestamp. Agents with stale heartbeats (>30 min, dead PID) are auto-removed by `list`.

### list
```bash
node cli.js list [--exclude ID] [--brief]
```
List active agents. Auto-removes stale agents. `--brief` prints one line per agent.

### send
```bash
node cli.js send --to NAME --message TEXT [--type info|alert|request|decision] [--from NAME]
node cli.js send --broadcast --message TEXT [--from NAME]
```
Send a message to a named agent or broadcast to all.

### inbox
```bash
node cli.js inbox --id ID [--ack]
```
Read messages for an agent. `--ack` deletes messages after reading.

### lock / unlock
```bash
node cli.js lock --file PATH --id ID [--reason TEXT]
node cli.js unlock --file PATH --id ID
```
Acquire and release advisory file locks.

### locks
```bash
node cli.js locks
```
List all active locks.

### context
```bash
node cli.js context --set KEY VALUE
node cli.js context --get KEY
node cli.js context --list
```
Set, get, or list shared context values (append-only JSONL, last write wins per key).

### track-file
```bash
node cli.js track-file --id ID --file PATH
```
Record that an agent is actively working on a file.

### who
```bash
node cli.js who --file PATH
```
Show which agents are tracking or locking a file.

---

## Usage in Practice

The `/mesh` command is the human-facing interface to the CLI. See [/mesh](commands/mesh.md) for the subcommand reference.

The `mesh-lifecycle.sh` hook handles register/deregister automatically at session boundaries. The `CLAUDE.md` coordination protocol describes when to check for agents, lock files, and share decisions before starting work.

---

## Stale Agent Cleanup

Agents are considered stale when:
- Their PID is no longer alive, AND
- Their last heartbeat is more than 30 minutes old

Stale agents are automatically removed by `list`. The 30-minute threshold accommodates long-running hooks where the Claude process is alive but not actively heartbeating.
