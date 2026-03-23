# Memory Data Model

This document describes the file formats used by the memory system.

## Directory structure

```
~/.claude/memory/
├── config.yaml           # System configuration
├── developer-edits.md    # Developer-controlled entries (via MCP tools)
├── generated.md          # Auto-generated context from session summaries
├── memory-context.md     # Combined injected block (what CLAUDE.md sees)
├── history.jsonl         # Append-only operation log
└── scripts/
    └── summarise_session.py  # Session summariser (generates generated.md)
```

## config.yaml

Controls memory system behaviour. All 7 fields are required.

```yaml
# Whether the memory system is active
enabled: true

# Whether to auto-regenerate generated.md at session end
auto_generate: true

# Maximum tokens for generated.md content
max_generated_tokens: 1500

# Maximum number of developer-controlled entries
max_developer_edits: 50

# Maximum character length per developer entry
max_edit_length: 500

# How memory is injected: "claude_md" (write to CLAUDE.md) or "system" (MCP injection)
injection_mode: claude_md

# Model to use for session summarisation
summariser_model: sonnet
```

## developer-edits.md

A numbered list of developer-controlled memory entries. Each entry is stored in third person.

```markdown
1. Prefers vitest over jest for testing
2. Uses pnpm as package manager
3. Working on a marketplace plugin system for Claude Code
4. SSH login always requires a password
```

### Format rules
- One entry per line
- Numbered sequentially starting from 1 (`N. content`)
- No blank lines between entries
- Entries are in third person ("Prefers X" not "I prefer X")
- No headings or metadata — just the numbered list

### MCP operations
- `memory_add`: Appends a new entry with the next number
- `memory_remove`: Removes by number, renumbers remaining entries
- `memory_replace`: Replaces content at a given number
- `memory_view`: Returns the full numbered list

## generated.md

Auto-generated context from session history. Produced by the summariser. Has 4 required sections:

```markdown
## Work context
Current projects, tech stacks, codebases the developer works in.

## Personal context
Preferences, conventions, tooling choices, communication style.

## Top of mind
Active tasks, recent decisions, ongoing investigations.

## Brief history
Compressed summary of recent session activity.
```

### Format rules
- Each section is an `##` heading
- Content under each heading is free-form prose or bullet lists
- Sections appear in the order listed above
- The summariser overwrites the entire file on each generation

## memory-context.md

The final injected block — what gets written into CLAUDE.md between `<!-- MEMORY:START -->` and `<!-- MEMORY:END -->` markers.

This file is assembled from:
1. The memory system overview and application instructions (static template)
2. Contents of `generated.md` (auto-generated context)
3. Contents of `developer-edits.md` (as `<userMemories>`)

### Format
```markdown
<memory_system>
<memory_overview>...</memory_overview>
<memory_application_instructions>...</memory_application_instructions>
<forbidden_memory_phrases>...</forbidden_memory_phrases>
<appropriate_boundaries_re_memory>...</appropriate_boundaries_re_memory>
<current_memory_scope>...</current_memory_scope>
<memory_safety>...</memory_safety>
</memory_system>

<userMemories>
<generated context from generated.md>

---

**Developer instructions**
<entries from developer-edits.md>
</userMemories>
```

## history.jsonl

Append-only log of memory operations. One JSON object per line.

### Entry format
```json
{"timestamp": "2026-03-17T10:30:00Z", "action": "added", "content": "Prefers vitest over jest"}
{"timestamp": "2026-03-17T10:35:00Z", "action": "removed", "entry_num": 3, "content": "Old entry text"}
{"timestamp": "2026-03-17T10:40:00Z", "action": "replaced", "entry_num": 2, "old": "Old text", "new": "New text"}
{"timestamp": "2026-03-17T11:00:00Z", "action": "regenerated", "token_count": 1200}
{"timestamp": "2026-03-17T12:00:00Z", "action": "reset"}
```

### Fields
- `timestamp`: ISO 8601 UTC timestamp
- `action`: One of `added`, `removed`, `replaced`, `regenerated`, `reset`
- Additional fields vary by action type (see examples above)
