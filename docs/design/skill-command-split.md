# Skill/Command Split Design

> Extracted from native-alignment-gap-analysis.md — Phase 2 design document

## Principle
- **Skills** = auto-triggered by conversation context (Claude decides when to invoke)
- **Commands** = user-invoked via /slash-command (user explicitly types it)

## Classification

### Keep as Skill (6)

| Skill | Reason |
|-------|--------|
| debug-investigator | Triggers on "this is broken", "not working" — organic conversation phrases |
| frontend-design | Triggers on "build a website", "redesign" — contextual auto-trigger |
| prompt-improver | Three modes, triggers on "improve prompt" — can match mid-conversation |
| task-manager | Triggers on "task status", "manage tasks" — always-available backbone |
| train | Triggers on "train", "run training" — could be either, keep as skill for now |
| improve | Self-improvement workflow — keep as skill, triggers on "improve", "self-improve" |

### Migrate to Command (8)

| Skill | Proposed Command | Needs $ARGUMENTS | Needs !backtick |
|-------|-----------------|------------------|-----------------|
| claude-code-guide | `commands/claude-code-guide.md` | Yes — `[topic]` | No |
| code-review | `commands/code-review.md` | Yes — `[file-or-branch]` | Yes |
| docs-manager | `commands/docs-manager.md` | Yes — `[init\|audit\|archive\|reindex]` | Yes |
| field-review | `commands/field-review.md` | Yes — `[--days N] [--submit]` | Yes |
| logs | `commands/logs.md` | Yes — `[subcommand] [args]` | Yes |
| memory | `commands/memory.md` | Yes — `[view\|add\|remove\|...]` | No |
| mesh | `commands/mesh.md` | Yes — `[status\|send\|lock\|decide]` | Yes |
| session-dashboard | `commands/session-dashboard.md` | Yes — `[last-N]` | Yes |

## Compact/Full Variant Resolution

**Decision:** Eliminate the variant pattern. Standardize on single SKILL.md files.

**Rationale:**
- Native Claude Code uses single SKILL.md — variants are non-standard
- 3 skills have SKILL.md as a no-frontmatter stub, making them non-functional
- The pattern is inconsistently inverted between skills

**Migration:**
- `code-review`: SKILL.md is already full — delete SKILL-COMPACT.md
- `prompt-improver`: SKILL.md is already full — delete SKILL-COMPACT.md
- `field-review`: Rename SKILL-FULL.md → SKILL.md (replace stub)
- `frontend-design`: Rename SKILL-FULL.md → SKILL.md (replace stub)
- `improve`: Rename SKILL-FULL.md → SKILL.md (replace stub)

## Non-Standard Frontmatter Resolution

| Field | Action |
|-------|--------|
| `context: fork` | Move to `metadata.context` if used by plugin loader, else remove |
| `agent: Explore` | Move to `metadata.agent` if used by plugin loader, else remove |
| `context: none` | Move to `metadata.context` if used, else remove |

## Command File Template

```markdown
---
description: [one-line description]
argument-hint: [usage hint]
---

[Skill body content, adapted to use $ARGUMENTS and !backtick injection]
```
