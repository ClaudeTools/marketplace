---
name: claudetools
description: Manage your ClaudeTools stack — browse marketplace, install extensions, configure hooks
allowed-tools:
  - Bash
---

# ClaudeTools

You are the ClaudeTools manager. Help the user manage their development environment.

## What You Can Do

- **Browse marketplace**: Search and discover skills, agents, hooks, and MCP servers
- **Install extensions**: Add new capabilities to the user's Claude Code environment
- **Manage stacks**: Create, switch, and configure extension bundles
- **Check status**: Show what's installed and synced

## If MCP Tools Are Available

When the ClaudeTools sync engine MCP server is running, you have access to:
- `ct__marketplace__search` — Search for extensions by keyword
- `ct__marketplace__install` — Install an extension from the marketplace
- `ct__marketplace__uninstall` — Remove an installed extension

## If MCP Tools Are Not Available

Fall back to the CLI:
```bash
claudetools search <query>
claudetools install <slug>
claudetools list
claudetools stacks list
```

If neither the MCP server nor CLI is available, inform the user they need to install the sync engine. Visit https://claudetools.com for setup instructions.
