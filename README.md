# ClaudeTools Marketplace

Plugin repository for the ClaudeTools platform. Contains the bootstrap plugin and CI-generated plugin directories from the marketplace API.

## Structure

```
marketplace/
├── .claude-plugin/marketplace.json   Root manifest listing all plugins
├── claudetools/                      Bootstrap plugin (ships with ClaudeTools)
│   ├── .claude-plugin/plugin.json    Plugin manifest
│   ├── skills/claudetools/SKILL.md   Marketplace skill definitions
│   ├── agents/claudetools.md         Management agent
│   ├── hooks/hooks.json              Session lifecycle hooks
│   └── .mcp.json                     MCP server configuration
├── plugins/                          CI-generated from marketplace API (gitignored)
└── .github/workflows/generate.yml    Daily plugin generation workflow
```

## How It Works

1. The **bootstrap plugin** (`claudetools/`) provides core marketplace functionality via MCP tools
2. The **generate workflow** runs daily to fetch approved extensions from the API and generate plugin directories under `plugins/`
3. Users install plugins through the marketplace UI or CLI, which copies plugin assets into their project

## Plugin Format

Each plugin is a directory containing a `.claude-plugin/plugin.json` manifest that declares:
- Skills (prompt templates in `skills/`)
- Agents (agent definitions in `agents/`)
- Hooks (lifecycle hooks in `hooks/`)
- MCP servers (`.mcp.json`)
