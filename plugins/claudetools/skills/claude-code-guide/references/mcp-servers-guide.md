# MCP Servers Guide

A reference for building, configuring, and integrating MCP (Model Context Protocol) servers with Claude Code. Covers when to use MCP servers vs hooks vs skills, tool description best practices, and real implementation patterns from the plugin codebase.

---

## 1. What MCP Servers Are

MCP servers are local processes that expose tools to Claude Code via the Model Context Protocol. They communicate over stdio (stdin/stdout) using JSON-RPC. Claude Code starts MCP servers automatically based on configuration in `settings.json` and keeps them running for the session.

MCP servers give Claude new capabilities: querying databases, managing tasks, searching memory, interacting with external APIs. Each tool the server exposes appears alongside Claude Code's built-in tools (Read, Edit, Bash, etc.) and follows the same tool-calling conventions.

### Key Properties

- **Persistent process**: MCP servers start when Claude Code starts and stay running. They are not invoked per-call like hooks.
- **Stateful**: Servers can maintain in-memory state across multiple tool calls within a session.
- **Stdio transport**: Communication is over stdin/stdout using JSON-RPC. No HTTP, no ports, no network.
- **Tool descriptions are your prompt budget**: Claude sees tool descriptions every turn. The description IS the instruction for when and how to use the tool.

---

## 2. When to Use MCP Servers vs Hooks vs Skills

### Decision Matrix

| Scenario | Use | Why |
|----------|-----|-----|
| React to a tool call or lifecycle event | **Hook** | Hooks fire on specific events (PostToolUse, Stop, SessionStart) |
| Provide new tools Claude can call | **MCP Server** | MCP servers expose tools in Claude's tool palette |
| Teach Claude a complex workflow | **Skill** | Skills load instructions on demand via SKILL.md |
| Persist data across sessions | **Hook + MCP Server** | Hook captures events; MCP server provides query/mutation tools |
| Run a script and return results | **MCP Server** | Tools return structured data Claude can reason about |
| Validate Claude's output before it executes | **Hook** | PreToolUse hooks can intercept and block actions |
| Coordinate between agents | **MCP Server** | Persistent process can manage locks, messages, shared state |

### The Layered Pattern

The plugin codebase uses a four-layer pattern where hooks, MCP servers, and skills each handle different concerns:

```
Layer 1: PERSIST  - Hooks capture events and write to disk
Layer 2: ENRICH   - MCP server provides tools for querying/mutating persisted data
Layer 3: TEACH    - Skill teaches Claude the extended workflow
Layer 4: CONNECT  - CLAUDE.md conventions tie everything together
```

Each layer adds value independently. A hook alone solves persistence. Adding the MCP server adds queryability. Adding the skill adds guided workflows.

---

## 3. MCP Server Configuration

### settings.json

MCP servers are configured in Claude Code's settings file (`.claude/settings.json` for project-scoped, `~/.claude/settings.json` for global):

```json
{
  "mcpServers": {
    "task-system": {
      "command": "node",
      "args": ["/absolute/path/to/server.js"],
      "env": {
        "TASK_SYSTEM_PROJECT_ROOT": "/path/to/project"
      }
    }
  }
}
```

Fields:
- `command`: the executable to run (usually `node`)
- `args`: arguments passed to the command (the server entry point)
- `env`: optional environment variables passed to the server process

### Bootstrap Pattern

MCP servers start before hooks, so they cannot rely on SessionStart hooks for dependency installation. Use a bootstrap wrapper that installs dependencies if missing:

```bash
#!/usr/bin/env bash
# start.sh - Bootstrap wrapper for MCP server
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$DIR/node_modules" ]]; then
  (cd "$DIR" && npm install --production --no-audit --no-fund 2>/dev/null) || true
fi

exec node "$DIR/server.js" "$@"
```

This pattern is used by `plugin/task-system/start.sh` in this codebase.

---

## 4. Tool Description Best Practices

Tool descriptions are the most important part of an MCP server. Claude sees them every turn, and they determine whether Claude uses the tool correctly.

### Anatomy of a Good Tool Description

Every tool description should contain:

1. **WHAT it does** (1-2 sentences)
2. **WHEN to use it** (trigger conditions)
3. **WHEN NOT to use it** (with specific alternatives)
4. **HOW to use it** (parameter guidance, common patterns)
5. **FAILURE MODES** (what goes wrong and how to avoid it)

### Two-Layer Architecture

If you control both the MCP server and the system prompt (via CLAUDE.md or a skill), split instructions across two layers:

- **Tool description** (thin): what the tool does, 1-3 lines
- **System prompt / SKILL.md** (detailed): how and when to use it, failure modes, examples

If you only control the MCP server (no skill, no CLAUDE.md), the tool description IS your entire prompt budget. Pack critical instructions into it.

### Parameter Descriptions

Include the expected type/format, constraints (min/max, valid enums), default behaviour when omitted, and examples of valid values. Use `enum` for constrained string values -- Claude follows enum constraints reliably.

---

## 5. Real Example: Task System MCP Server

The plugin's task system (`plugin/task-system/`) demonstrates the full MCP server pattern.

### Server Structure

```
plugin/task-system/
  start.sh              # Bootstrap wrapper (installs deps, starts server)
  server.js             # MCP server entry point
  lib/tools.js          # Tool definitions and handlers
  package.json          # Dependencies (@modelcontextprotocol/sdk)
```

### Server Entry Point Pattern

The server creates a `Server` instance with `{ capabilities: { tools: {} } }`, registers `ListToolsRequestSchema` to return tool definitions, and registers `CallToolRequestSchema` to dispatch tool calls. It connects via `StdioServerTransport`. See `plugin/task-system/server.js` for the full implementation.

### Error Handling

The server handles process-level errors to prevent crashes: ignore `SIGPIPE` (client disconnect), log `uncaughtException` and `unhandledRejection` to stderr, exit cleanly on `EPIPE`/`SIGINT`/`SIGTERM`.

---

## 6. Implementation Constraints

### Dependencies

Use only Node.js built-in modules plus the MCP SDK. No other dependencies. This keeps installation trivial and avoids dependency conflicts.

```bash
cd my-mcp-server && npm init -y && npm install @modelcontextprotocol/sdk
```

Set `"type": "module"` in `package.json` for ESM imports.

### Local-Only

MCP servers in this codebase are strictly local. They never call external APIs or network services. Everything is local file I/O. Integration with external services (Jira, GitHub Issues) is out of scope for the core system.

### Concurrent Access

Both hooks and MCP servers may write to the same files. Use atomic writes to prevent corruption:

```javascript
function atomicWrite(filePath, data) {
  const tmp = filePath + '.tmp.' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, filePath);
}
```

For append-only logs (`history.jsonl`), use `fs.appendFileSync()` which is append-safe on POSIX systems.

### Input Validation

Validate all inputs before writing. Return structured errors with field names and expected types. Never trust input shape without checking.

---

## 7. Gotchas

### Server Lifecycle

MCP servers start when Claude Code starts and persist for the session. If the server crashes, Claude Code may not restart it automatically. Build robust error handling and avoid unhandled promise rejections.

### Tool Naming

Tool names are globally unique across all MCP servers. If two servers expose a tool with the same name, behaviour is undefined. Use a namespace prefix when the tool name might collide (e.g., `task_create` not just `create`).

### Schema Design

- Keep input schemas flat. Deeply nested objects are harder for Claude to construct correctly.
- Use enums for constrained string values. Claude follows enum constraints reliably.
- Make parameters optional with sensible defaults rather than requiring everything.
- Return structured JSON, not freeform text. Claude parses JSON results more reliably.

### Tool Description Length

Tool descriptions are injected every turn. Long descriptions (500+ words) consume context window space on every turn. Keep descriptions concise and move detailed instructions to a skill's SKILL.md or CLAUDE.md, which loads on demand.

### MCP Server Priority

Claude Code prioritises MCP tools over its built-in alternatives when the MCP tool is a better fit. If your MCP server provides a task creation tool, Claude will prefer it over TodoWrite for structured task management. Make sure tool descriptions clearly state when the tool should and should not be used.

---

## 8. Verification Checklist

```
[ ] Server starts without errors when run directly: node server.js
[ ] Server handles SIGPIPE, uncaughtException, and EPIPE gracefully
[ ] All tools have descriptions with what/when/when-not/how guidance
[ ] Input schemas use enums for constrained values
[ ] All file writes use atomic write pattern
[ ] No external network calls (local-only)
[ ] Dependencies are minimal (MCP SDK + Node.js built-ins)
[ ] Bootstrap wrapper (start.sh) handles first-run dependency install
[ ] Tool names are namespaced to avoid collisions
[ ] settings.json configuration uses absolute paths
[ ] Error responses include structured error messages
[ ] Server handles concurrent access from hooks safely
```

---

## Cross-References

- For tool routing and preference ordering patterns, see `prompting-guide.md`
- For settings.json and CLAUDE.md integration, see `claude-md-guide.md`
- For the task system MCP server as a worked example, see `memory-task-guide.md`
