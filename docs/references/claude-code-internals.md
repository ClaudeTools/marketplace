# Claude Code Internals — Token Efficiency Reference

Source analysis from Claude Code v2.1.84 (`src/` archive, March 2026).

## Hook Output Processing

### What reaches the model's context

| Event | stdout (plain text, exit 0) | stdout (JSON) | stderr | exit 2 stderr |
|-------|----------------------------|---------------|--------|---------------|
| SessionStart | **YES** — `<system-reminder>` | `additionalContext` field only | No | **YES** (blocking error) |
| UserPromptSubmit | **YES** — `<system-reminder>` | `additionalContext` field only | No | **YES** (blocking error) |
| PreToolUse | **No** (dropped) | block/allow JSON protocol | No | **YES** (blocking error) |
| PostToolUse | **No** (dropped) | `additionalContext` field only | No | **YES** (blocking error) |

Key source: `messages.ts:4099-4115` — `hook_success` attachments are only converted to API messages for `SessionStart` and `UserPromptSubmit`. All other events: `return []`.

### Implication for our hooks

- **PostToolUse hooks writing to stdout at exit 0**: Text is stored in UI attachment but **never sent to the model**. Our `capture-outcome.sh`, `track-file-reads.sh`, `edit-frequency-guard.sh` writing to stderr was already correct — but even stdout wouldn't have reached the model.
- **PostToolUse hooks writing to stderr at exit 1**: Also never reaches the model. Only exit 2 stderr reaches the model.
- **verify-subagent-independently.sh fix was correct**: SubagentStop hooks use the same PostToolUse path. The stdout lines 94-95 were appearing in the UI but NOT reaching the model. However, routing to stderr is still better practice for clarity.

**Wait — correction**: The `hook_success` at `messages.ts:4099` checks `hookEvent`. For SubagentStop, this is a different event type. Need to verify if SubagentStop maps to PostToolUse or has its own handler. The safest approach (which we took) is stderr for status messages.

### No output size limit

There is **no truncation limit** on hook stdout/stderr. The full accumulated output from the child process is used as-is. The only limit is the 10-minute execution timeout (`TOOL_HOOK_EXECUTION_TIMEOUT_MS`).

### async: true hooks

When a hook outputs `{"async": true}` as its first line, the hook runner immediately returns success and the process continues in background. Output is polled on subsequent turns via `AsyncHookRegistry.checkForAsyncHookResponses()`. The `systemMessage` and `additionalContext` from the async response are injected when the poll detects completion — wrapped in `<system-reminder>`.

## System Prompt Assembly

Order (from `prompts.ts:444-577`):

1. Identity framing
2. Tool use rules
3. Coding behavior rules
4. Reversibility/blast-radius rules
5. Tool preferences
6. Tone/style
7. Output efficiency
8. **`__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__`** — everything after this breaks prompt cache
9. Dynamic sections: `session_guidance`, `memory`, `env_info`, `mcp_instructions` (uncached), `scratchpad`, etc.

### MCP instructions are uncached

`mcp_instructions` uses `DANGEROUS_uncachedSystemPromptSection` — it recomputes every turn because MCP servers can connect/disconnect. This means MCP tool descriptions break the prompt cache every time they change.

## Context Injection — No Plugin Limit

- **CLAUDE.md files**: Loaded in full, no per-file size limit. All flow through `getClaudeMds()` → `prependUserContext()` → `<system-reminder>` block untruncated.
- **Rules files** (`.claude/rules/*.md`): Loaded via `processMdRules()`. Files with `paths:` frontmatter are conditional (only injected when working file matches). Files with empty `paths:` or `paths: ["**/*"]` are effectively unconditional.
- **MEMORY.md**: Hard limit of **200 lines or 25,000 bytes** (whichever fires first). Excess is truncated with a warning.
- **Git status**: Truncated at **2,000 characters**.

### Our plugin's context footprint

| Source | Size | Frequency |
|--------|------|-----------|
| rules/*.md (12 files, all `paths: **/*`) | ~17.9KB (~4,500 tokens) | Every turn |
| MEMORY.md index | Variable, cap 200 lines/25KB | Every turn |
| SessionStart hook stdout | ~200-600 bytes | Once per session |
| UserPromptSubmit hook stdout | ~100-300 bytes | Every user message |
| MCP tool descriptions (task-system + think) | ~500 bytes | Every turn (uncached) |
| Skill listings in system-reminder | ~3,000-4,000 tokens | Every turn |

## Compaction Behavior

When auto-compact fires:
- All raw message history before the boundary is compressed into a structured 9-section summary
- System prompt and userContext (CLAUDE.md, rules, MEMORY.md) are NOT compacted — they remain full size every turn
- Recently read files (up to 5, at 5K tokens each) are re-injected as attachments
- Invoked skills are re-injected (up to 25K total budget)
- All `systemPromptSection` caches are cleared, forcing CLAUDE.md and MEMORY.md to be re-read

### Implication

Rules files and CLAUDE.md content survive compaction unchanged. They are the irreducible baseline context cost. Every byte saved from rules files saves that byte on every single turn for the entire session.

## MCP Tool Descriptions — Deferred by Default

**Critical finding**: MCP tools are **deferred by default** via the ToolSearch system (`isDeferredTool` in `ToolSearchTool/prompt.ts:62`). When deferred:
- Only tool **names** are announced in a `<system-reminder>` (not descriptions/schemas)
- Full descriptions are only loaded when the model calls `ToolSearchTool(query: "select:mcp__server__tool")`
- MCP descriptions are **truncated at 2048 characters** (`MAX_MCP_DESCRIPTION_LENGTH` in `mcp/client.ts:213`)

**Exception**: Tools with `_meta['anthropic/alwaysLoad'] === true` bypass deferral.

**Implication for our think MCP**: The tool description (~20 tokens) is only loaded when the model uses ToolSearch to select it. The old sequential-thinking description (~400 tokens) was similarly deferred. The real savings from our replacement come from:
1. Leaner per-call JSON responses (no pretty-printing, fewer fields)
2. Auto-summarization preventing context bloat in long thinking chains
3. Not depending on an external npm package

## Skill Listing Budget

Skill listings are NOT unbounded. `formatCommandsWithinBudget` in `SkillTool/prompt.ts:70` enforces:
- **1% of context window** total budget (~8,000 chars for 200k models)
- **250 chars max** per skill entry
- Bundled skills (Anthropic's) get full descriptions; plugin skills are proportionally trimmed
- With experimental skill-search: filtered to 30 skills max (bundled + MCP)

Skills are listed once per session via `skill_listing` attachment, with delta updates for new skills.

## Skill Invocation

When invoked via the Skill tool, the full SKILL.md content enters as a user message. Post-compaction, invoked skills are restored from `STATE.invokedSkills` (up to 25K total budget, 5K per skill).

Skill names are namespaced: `pluginName:skillName` (e.g., `claudetools:design`). The duplicate listings we see are from multiple plugins having skills with matching functionality descriptions — not actual duplicate files within one plugin.

## Optimization Priorities (based on source analysis)

1. **Rules files** — 17.9KB loaded every turn, survives compaction. Biggest savings per byte. (~4,500 tokens/turn)
2. **Skill listings** — Budgeted at 1% context but still ~3-4K tokens. Can't reduce without removing skills.
3. **MCP descriptions** — Deferred by default, but truncated at 2048 chars. Keep descriptions lean for when they ARE loaded.
4. **SessionStart stdout** — one-time but stays in context. Already optimized.
5. **UserPromptSubmit stdout** — per-turn. Already optimized with caching and dedup.
6. **Skill file sizes** — Only matter when invoked + post-compaction restoration. Our extraction of prompt-improver's agent prompt saves ~1400 tokens per invocation.
