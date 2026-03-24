# Hook Consolidation Design

> Extracted from native-alignment-gap-analysis.md — Phase 2 design document

## Goal
Slim hooks.json from 432 lines to ~120-150 lines by migrating behavioral text injection to rules/ and consolidating overlapping scripts.

## Scripts to Remove from hooks.json

### MIGRATE-TO-RULE (remove hook entry, create rule file)

| Script | Event | New Rule File | Rule Content |
|--------|-------|---------------|--------------|
| `dynamic-rules.sh` | InstructionsLoaded | `rules/project-tooling.md` | Project type detection → build/test/lint commands table. Claude reads package.json itself. Also extract "save learnings to memory/" → `rules/memory-discipline.md` |
| `enforce-memory-preferences.sh` | PreToolUse:Edit\|Write\|Bash | `rules/memory-enforcement.md` | "Before writing code or running commands, check MEMORY.md for stored feedback. If action contradicts ALWAYS/NEVER preference, re-read the memory." **Note:** Keep the pattern-matching exit-code portion as a hook; only migrate the text injection. |
| `inject-session-context.sh` (partial) | SessionStart | `rules/session-orientation.md` | Static session boilerplate + churn/failure behavioral guidance. DB-derived dynamic content stays as hook. |

### New Rule Files to Create

```markdown
# rules/project-tooling.md
---
paths:
  - "**/*"
---
## Project Verification Commands

Detect the project type from config files and use the appropriate commands:

| Config File | Typecheck | Test | Lint |
|-------------|-----------|------|------|
| package.json (TypeScript) | `npx tsc --noEmit` | `npm test` | `npx eslint .` |
| Cargo.toml | `cargo check` | `cargo test` | `cargo clippy` |
| pyproject.toml / setup.py | `mypy .` | `pytest` | `ruff check .` |
| go.mod | `go vet ./...` | `go test ./...` | `golangci-lint run` |

Read the project's config file to determine which row applies. Run typecheck after each change. Run tests before committing.
```

```markdown
# rules/memory-discipline.md
---
paths:
  - "**/*"
---
Save learnings to memory/ when you discover project patterns, user preferences, or make significant decisions that would be valuable in future sessions.
```

```markdown
# rules/memory-enforcement.md
---
paths:
  - "**/*"
---
Before writing code or running commands, check MEMORY.md for stored feedback preferences marked with ALWAYS or NEVER. If your planned action contradicts a stored preference, re-read the relevant memory file to understand the constraint before proceeding.
```

```markdown
# rules/session-orientation.md
---
paths:
  - "**/*"
---
At session start:
- When edit churn from recent sessions is high, prioritize diagnostics before editing.
- When failure rate is elevated, research before implementing.
- Review active tasks and in-progress work before starting new work.
```

## Consolidation Changes

### Group 1: Worktree enforcement
- **Action:** Remove `[agent-mesh] MANDATORY: Call EnterWorktree...` echo from `mesh-lifecycle.sh` register action
- **Reason:** `enforce-worktree-isolation.sh` already hard-blocks with exit 2

### Group 2: Quality gate unification
- **Action:** Refactor `enforce-task-quality.sh` (TeammateIdle) to source `validators/task-quality.sh` instead of inline reimplementation
- **Reason:** Inline code diverges from validator (different regex, thresholds)

### Group 3: Memory extraction pipeline
- **Action:** Consolidate `memory-reflect.sh` + `session-learn-negatives.sh` into single Stop hook with two extraction phases
- **Action:** Evaluate `validators/memory-deep.sh` — remove if it duplicates `memory-reflect.sh`

## Expected hooks.json Size
After removals: ~120-150 lines (down from 432)
