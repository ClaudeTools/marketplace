---
name: memory
description: Manage developer memory — persistent cross-session knowledge. Use when the user says /memory, remember this, forget this, what do you remember, or manage memory.
argument-hint: [view|show|add|remove|replace|regenerate|status|reset|export] [args]
allowed-tools: Read, Bash, Grep, Glob
metadata:
  author: Owen Innes
  version: 1.0.0
  category: memory
  tags: [memory, persistence, developer-context]
---

# Memory Management

You are executing the `/memory` skill. This is a subcommand router for the developer memory system. It provides persistent, cross-session knowledge that is injected into every conversation via CLAUDE.md.

Parse the first argument to select the subcommand. Default to a status overview if no argument is given.

## Natural language triggers

Before parsing subcommands, check if the user's message matches a natural language pattern:

| Pattern | Action |
|---------|--------|
| "remember that..." / "don't forget..." | Treat as `add` with the content after the trigger phrase |
| "forget about..." / "please forget..." | Treat as `remove` — match the content against existing entries |
| "update your memory..." | Treat as `replace` — match existing entry, replace with new content |
| "what do you remember?" | Treat as `view` plus show a generated summary |

---

### (no args) — Status overview

Show a quick status of the memory system.

1. Call the MCP `memory_view` tool to get current developer-controlled entries.
2. Count the entries returned.
3. Check if `~/.claude/memory/memory-context.md` exists and read its last-modified timestamp.
4. Display:
   - Number of developer-controlled entries
   - Last generation timestamp (or "never generated" if file does not exist)
   - Quick config status (enabled, auto_generate, injection_mode from `~/.claude/memory/config.yaml`)

---

### view

Show the developer-controlled memory entries.

1. Call the MCP `memory_view` tool.
2. Display the numbered list of entries exactly as returned.
3. If no entries exist, tell the user: "No memory entries yet. Use `/memory add \"...\"` or say 'remember that...' to add one."

---

### show

Show the full injected memory block — what Claude Code actually sees at the start of each conversation.

1. Read `~/.claude/memory/memory-context.md`.
2. Display the full contents in a code fence.
3. If the file does not exist, tell the user: "No memory context file found. Run `/memory regenerate` to generate one."

---

### add

Add a new developer-controlled memory entry.

1. Parse the remaining arguments as the entry content (strip surrounding quotes if present).
2. Call the MCP `memory_view` tool to get existing entries.
3. Check for duplicates — if an existing entry is semantically very similar, warn the user and ask whether to proceed.
4. Rewrite the entry to third person if it is written in first person (e.g., "I prefer tabs" → "Prefers tabs over spaces").
5. Call the MCP `memory_add` tool with the rewritten entry.
6. Confirm: **"Noted."**

---

### remove

Remove a developer-controlled memory entry by number.

1. Parse the remaining argument as an entry number (1-indexed).
2. Call the MCP `memory_view` tool to get all entries.
3. Display the entry that will be removed: "Will remove entry N: <content>"
4. Ask for confirmation: "Proceed? (yes/no)"
5. On confirmation, call the MCP `memory_remove` tool with the entry number.
6. Confirm: "Removed."

---

### replace

Replace a developer-controlled memory entry.

1. Parse: first argument is the entry number, remaining arguments are the new content.
2. Call the MCP `memory_view` tool to get all entries.
3. Display the change: "Will replace entry N:\n  Old: <old content>\n  New: <new content>"
4. Ask for confirmation: "Proceed? (yes/no)"
5. On confirmation, call the MCP `memory_replace` tool with the entry number and new content.
6. Confirm: "Updated."

---

### regenerate

Force re-generation of the generated memory context.

1. Read session history and any available context.
2. Run the summariser to produce a new `generated.md`:
```bash
python3 ~/.claude/memory/scripts/summarise_session.py
```
3. If the summariser script does not exist or fails, tell the user: "Summariser not available. Check setup with `/memory status`."
4. Confirm: "Memory context regenerated."

---

### status

Run the memory stats script for a full diagnostic report.

1. Run the stats script:
```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/memory_stats.py"
```
2. Display the output to the user.
3. If the script fails, fall back to manual checks:
   - Check if `~/.claude/memory/` directory exists
   - Check if `config.yaml`, `developer-edits.md`, `generated.md`, `history.jsonl` exist
   - Report what is present and what is missing

---

### reset

Delete all memory data. This is destructive and requires explicit confirmation.

1. Display warning:
   ```
   ⚠ This will delete ALL memory data:
     - developer-edits.md (your manual entries)
     - generated.md (auto-generated context)
     - history.jsonl (operation history)
     - memory-context.md (injected context)

   Config will be preserved.
   ```
2. Ask for explicit confirmation: "Type 'yes' to confirm reset."
3. On confirmation, remove the listed files (NOT config.yaml).
4. Confirm: "Memory reset complete. Config preserved."

---

### export

Export the full memory state as a single markdown document.

1. Read `~/.claude/memory/developer-edits.md` (if exists).
2. Read `~/.claude/memory/generated.md` (if exists).
3. Read `~/.claude/memory/config.yaml` (if exists).
4. Combine into a single markdown document:
   ```markdown
   # Memory Export — <timestamp>

   ## Developer Entries
   <contents of developer-edits.md, or "None">

   ## Generated Context
   <contents of generated.md, or "None">

   ## Configuration
   <contents of config.yaml>
   ```
5. Display the export to the user.

---

## Memory application rules

When memory content is injected into conversations, these rules govern how it is applied.

### Forbidden phrases

Memory requires no attribution. Claude Code never draws attention to the memory system itself except when directly asked about what it remembers.

**NEVER use observation verbs suggesting data retrieval:**
- "I can see..." / "I see..." / "Looking at..."
- "I notice..." / "I observe..." / "I detect..."
- "According to..." / "It shows..." / "It indicates..."

**NEVER make references to external data about the developer:**
- "...what I know about you" / "...your information"
- "...your memories" / "...your data" / "...your profile"
- "Based on your memories" / "Based on Claude's memories"
- "Based on..." / "From..." / "According to..." when referencing ANY memory content
- ANY phrase combining "Based on" with memory-related terms

**NEVER include meta-commentary about memory access:**
- "I remember..." / "I recall..." / "From memory..."
- "My memories show..." / "In my memory..."
- "According to my knowledge..."

**MAY use these phrases ONLY when the developer directly asks about what Claude Code remembers:**
- "As we discussed..." / "In our past sessions..."
- "You mentioned..." / "You've shared..."

### Application tiers

**NEVER apply memory for:**
- Generic technical questions requiring no personalisation
- Content that reinforces unsafe, unhealthy, or harmful behaviour
- Contexts where personal details would be surprising or irrelevant

**ALWAYS apply relevant memory for:**
- Code generation: use developer's observed naming conventions, import style, patterns
- Tool usage: use preferred package manager, test runner, linter
- Git operations: use preferred commit format, branching conventions
- Explicit requests: "based on what you know about my setup"
- Tool calls: use memory to inform tool parameters silently

**SELECTIVELY apply memory for:**
- Error debugging: reference known recurring issues silently
- Communication style: apply formatting and language preferences
- Project context: reference active projects when relevant
- Technical depth: match the developer's expertise level

---

## Conditional references

- Load [references/memory-schema.md](references/memory-schema.md) when working with memory file formats, debugging validation errors, or understanding the data model.
- Load [references/application-rules.md](references/application-rules.md) when handling memory application logic, forbidden phrases, or ownership rules.
- Load [references/setup-guide.md](references/setup-guide.md) when the memory system is not configured, MCP server is not running, or when troubleshooting setup issues.

---

## Gotchas

- **All memory operations go through MCP tools.** The skill does not read/write memory files directly, except for `show` (reads the injected file) and `status` (reads files for diagnostics).
- **Always show before destructive ops.** For `remove` and `replace`, ALWAYS display what will change and get confirmation before proceeding.
- **Third person rewriting.** Developer entries are stored in third person ("Prefers X" not "I prefer X") so they read naturally when injected into the system prompt.
- **Duplicate detection.** Before adding, check existing entries for semantic overlap to avoid redundancy.
- **Config is sacred.** The `reset` command never deletes `config.yaml` — only content files.
