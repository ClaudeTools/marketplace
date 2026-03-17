# Memory System Setup Guide

## Prerequisites

- Claude Code CLI installed
- MCP server plugin system configured
- Python 3.8+ available (for validation/stats scripts)

## Installation

### Step 1: Create the memory directory

```bash
mkdir -p ~/.claude/memory/scripts
```

### Step 2: Create the config file

Create `~/.claude/memory/config.yaml`:

```yaml
enabled: true
auto_generate: true
max_generated_tokens: 1500
max_developer_edits: 50
max_edit_length: 500
injection_mode: claude_md
summariser_model: sonnet
```

### Step 3: Initialise content files

```bash
# Create empty developer edits file
touch ~/.claude/memory/developer-edits.md

# Create empty history log
touch ~/.claude/memory/history.jsonl
```

### Step 4: Register the MCP server

The memory MCP server provides the `memory_view`, `memory_add`, `memory_remove`, and `memory_replace` tools. Register it in your Claude Code MCP configuration:

```json
{
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": ["path/to/memory/mcp-server/index.js"],
      "env": {
        "MEMORY_DIR": "~/.claude/memory"
      }
    }
  }
}
```

### Step 5: Register the session hook

The session-end hook triggers auto-generation of memory context. Add to your Claude Code settings:

```json
{
  "hooks": {
    "PostSessionEnd": [
      {
        "command": "python3 ~/.claude/memory/scripts/summarise_session.py",
        "timeout": 30000
      }
    ]
  }
}
```

### Step 6: Add CLAUDE.md markers

Add the memory injection markers to your CLAUDE.md (global or project-level):

```markdown
<!-- MEMORY:START -->
<!-- MEMORY:END -->
```

The memory system will write injected content between these markers.

### Step 7: Verify setup

Run the validation script:

```bash
python3 path/to/memory/scripts/validate_memory.py
```

Run the stats script:

```bash
python3 path/to/memory/scripts/memory_stats.py
```

Both should complete without errors.

## Troubleshooting

### "Memory directory not found"

The `~/.claude/memory/` directory does not exist. Create it:
```bash
mkdir -p ~/.claude/memory/scripts
```

### "config.yaml does not exist"

The config file is missing. Create it with the template from Step 2 above.

### "MCP tools not available" / memory_view not found

The memory MCP server is not registered or not running. Check:
1. MCP server is listed in your Claude Code configuration
2. The server process is running (`ps aux | grep memory`)
3. The server path is correct

### "Summariser not available"

The `summarise_session.py` script is missing or not executable. Check:
1. File exists at `~/.claude/memory/scripts/summarise_session.py`
2. Python 3 is available: `python3 --version`

### "MEMORY:START/END markers not found"

The injection hook cannot find markers in CLAUDE.md. Add them:
```markdown
<!-- MEMORY:START -->
<!-- MEMORY:END -->
```

### Generated context is empty or stale

- Check `auto_generate` is `true` in config
- Check the session-end hook is registered
- Run `/memory regenerate` to force regeneration
- Check `history.jsonl` for recent "regenerated" entries

### Developer edits not appearing in injected context

- Run `/memory view` to verify entries exist
- Check that `injection_mode` is set to `claude_md`
- Run `/memory regenerate` to force re-injection
- Verify CLAUDE.md markers are present and not malformed

### Token count too high

If the estimated token count is very high:
- Reduce `max_generated_tokens` in config
- Remove unnecessary developer entries with `/memory remove N`
- Run `/memory regenerate` to produce a more compact summary
