# Native .claude/ Alignment — Gap Analysis

> Audit date: 2026-03-24
> Scope: claudetools plugin v3.11.0 vs canonical .claude/ folder conventions

---

## 1. Executive Summary

The claudetools plugin currently ships 38 hook scripts, 31 validators, 14 skills, 6 rules, and 4 agents. After auditing every component against native Claude Code conventions:

| Metric | Value |
|--------|-------|
| Components fully aligned with native conventions | ~45% |
| Components needing structural migration | ~30% |
| Components needing consolidation or cleanup | ~15% |
| Components to deprecate | ~10% |

**Key gaps:**
- **8 of 14 skills** are user-invoked workflows masquerading as auto-triggered skills — they should be commands/
- **3-5 hook scripts** inject behavioral text via stdout instead of using rules/ files
- **No rules use path-scoping** — all 6 rules apply unconditionally via `**/*`
- **Compact/Full skill variants** are a non-standard pattern with inconsistent implementation
- **1 rule** (`codebase-navigation.md`) has no YAML frontmatter at all
- **2 rules** have significant content overlap (`deterministic-over-ai.md` and `no-shortcuts.md`)
- **3 groups** of hook scripts have consolidation opportunities (worktree enforcement, quality gates, memory extraction)

**What's working well:**
- Hook gate/dispatcher/validator architecture is sound and should be preserved
- Agent definitions are well-scoped with proper tool restrictions (except test-writer)
- Most hooks are genuine runtime gates that cannot be replaced by static rules
- `verify-subagent-independently.sh` is one of the highest-value hooks in the system

---

## 2. Hook Architecture Gaps

### 2.1 Hook Inventory Summary

| Category | Count | Scripts |
|----------|-------|---------|
| KEEP-AS-HOOK | 24 | Core gates, dispatchers, stateful trackers, side-effect hooks |
| MIGRATE-TO-RULE | 3-5 | `enforce-memory-preferences.sh`, `dynamic-rules.sh`, partial `inject-session-context.sh` |
| CONSOLIDATE | 3 groups | Worktree enforcement, quality gates, memory extraction |
| DEPRECATE | 2-3 | Potential duplicates in memory pipeline (`memory-deep.sh` vs `memory-reflect.sh`) |

### 2.2 MIGRATE-TO-RULE Candidates

| Script | Event | Behavioral Text Injected | Proposed Rule |
|--------|-------|--------------------------|---------------|
| `dynamic-rules.sh` | InstructionsLoaded | Static project tooling commands ("Typecheck: npx tsc --noEmit \| Test: npm test") | `rules/project-tooling.md` — table of project types to commands; Claude reads package.json itself |
| `enforce-memory-preferences.sh` | PreToolUse:Edit\|Write\|Bash | "MEMORY PREFERENCE CONFLICT: Your action may contradict stored preference: {match}" | `rules/memory-enforcement.md` — "Check MEMORY.md before acting"; keep pattern-matching portion as hook |
| `inject-session-context.sh` (partial) | SessionStart | Session boilerplate, churn/failure warnings | `rules/session-orientation.md` — standing behaviors; DB-derived content stays as hook |
| `dynamic-rules.sh` (memory portion) | InstructionsLoaded | "Save learnings to memory/ when you discover project patterns" | `rules/memory-discipline.md` — unconditional standing instruction |

### 2.3 CONSOLIDATE Groups

**Group 1: Worktree enforcement duplication**
- `enforce-worktree-isolation.sh` hard-blocks with exit 2
- `mesh-lifecycle.sh register` emits redundant MANDATORY warning
- **Action:** Remove worktree echo from mesh-lifecycle.sh; isolation hook is authoritative

**Group 2: Quality gate duplication**
- `enforce-task-quality.sh` (TeammateIdle) re-implements logic already in `validators/task-quality.sh`
- `session-stop-dispatcher.sh` and `task-completion-gate.sh` both source `validate_task_quality`
- **Action:** Refactor `enforce-task-quality.sh` to source validators/task-quality.sh instead of inline reimplementation

**Group 3: Memory extraction pipeline**
- 3 async AI calls at Stop (`memory-extract-fast.sh`, `memory-reflect.sh`, `session-learn-negatives.sh`)
- Plus `validators/memory-deep.sh` at SessionEnd — potential 4th pass
- **Action:** Consolidate `memory-reflect.sh` + `session-learn-negatives.sh` into single Stop hook; evaluate `memory-deep.sh` for removal

### 2.4 DEPRECATE Candidates

| Script | Reason |
|--------|--------|
| `validators/memory-deep.sh` | Likely duplicates `memory-reflect.sh` — both call claude CLI for memory extraction |
| `validators/aggregate-session.sh` vs `session-wrap.sh` | Both run at SessionEnd; may overlap with memory-reflect |

---

## 3. Skill/Command Alignment Gaps

### 3.1 Classification Results

| Classification | Count | Skills |
|----------------|-------|--------|
| **Keep as Skill** | 6 | debug-investigator, frontend-design, prompt-improver, task-manager, train (debatable), improve (debatable) |
| **Migrate to Command** | 8 | claude-code-guide, code-review, docs-manager, field-review, logs, memory, mesh, session-dashboard |
| **Deprecate** | 0 | — |

### 3.2 Compact/Full Variant Pattern

**Status:** Non-standard, inconsistently implemented.

| Pattern | Skills | Problem |
|---------|--------|---------|
| SKILL.md = full, SKILL-COMPACT.md = stub | code-review, prompt-improver | Works correctly — Claude loads SKILL.md |
| SKILL.md = compact stub (no frontmatter), SKILL-FULL.md = full | field-review, frontend-design, improve | **Broken** — Claude loads SKILL.md which has no frontmatter, so skill won't register |

**Recommendation:** Standardize on single SKILL.md files. Use progressive disclosure within one file (summary at top, detail below). Eliminate the variant pattern entirely.

### 3.3 Non-Standard Frontmatter Fields

| Field | Found In | Native? |
|-------|----------|---------|
| `context: fork` | code-review, docs-manager, session-dashboard, train | No — plugin-specific execution hint |
| `agent: Explore` / `agent: general-purpose` | code-review, docs-manager, session-dashboard | No — plugin-specific subagent routing |
| `context: none` | logs | No — plugin-specific |

**Recommendation:** Move to `metadata:` block if these fields serve a purpose, or remove if unused by the skill loader.

### 3.4 Broken References

| Skill | Issue | Severity |
|-------|-------|----------|
| train | `${CLAUDE_PLUGIN_ROOT}/scripts/tune-weights.sh` does not exist | **High** — broken subcommand |
| memory | `~/.claude/memory/scripts/summarise_session.py` is external to plugin | Medium — graceful degradation |

---

## 4. Rules and Agents Gaps

### 4.1 Rules Issues

| Issue | Affected | Severity |
|-------|----------|----------|
| Missing frontmatter entirely | `codebase-navigation.md` | High |
| No rules use path-scoping | All 6 rules use `**/*` | Medium |
| Content duplication | `deterministic-over-ai.md` overlaps `no-shortcuts.md` lines 39-45 | Medium |
| Stale skill references | `task-management.md` references `/task-manager restore` etc. | Low |

### 4.2 Agents Issues

| Issue | Affected | Severity |
|-------|----------|----------|
| Missing `disallowedTools` | `test-writer.md` — can edit any file | High |
| No `haiku` model usage | `researcher.md`, `code-reviewer.md` are read-only but use `sonnet` | Low (cost optimization) |

### 4.3 New Rules from Hook Migrations

| Proposed Rule | Source Hook | Path Scope | Priority |
|---------------|------------|------------|----------|
| `rules/project-tooling.md` | `dynamic-rules.sh` | `**/*` (or per-language) | High |
| `rules/memory-discipline.md` | `dynamic-rules.sh` | `**/*` | High |
| `rules/memory-enforcement.md` | `enforce-memory-preferences.sh` | `**/*` | Medium |
| `rules/session-orientation.md` | `inject-session-context.sh` | `**/*` | Medium |

---

## 5. Structural Recommendations — Proposed Directory Layout

```
plugin/
├── hooks/
│   └── hooks.json              # Slimmed to ~120-150 lines (genuine gates only)
├── scripts/
│   ├── gates/                  # Renamed from root — pure gate dispatchers
│   ├── validators/             # Unchanged — validator functions
│   ├── lifecycle/              # Session/mesh lifecycle hooks
│   ├── telemetry/              # capture-outcome, capture-failure, memory extraction
│   └── lib/                    # Unchanged — shared libraries
├── commands/                   # NEW — 8 migrated user-invoked workflows
│   ├── code-review.md
│   ├── claude-code-guide.md
│   ├── docs-manager.md
│   ├── field-review.md
│   ├── logs.md
│   ├── memory.md
│   ├── mesh.md
│   └── session-dashboard.md
├── skills/                     # Reduced to 6 auto-triggered skills
│   ├── debug-investigator/
│   ├── frontend-design/
│   ├── prompt-improver/
│   ├── task-manager/
│   ├── train/
│   └── improve/
├── rules/                      # Expanded from 6 to ~10 with proper frontmatter
│   ├── codebase-navigation.md  # Fixed: add frontmatter
│   ├── use-teams.md
│   ├── task-management.md      # Updated: remove stale skill refs
│   ├── deterministic-over-ai.md
│   ├── debugging-discipline.md
│   ├── no-shortcuts.md         # Deduplicated: remove overlapping section
│   ├── project-tooling.md      # NEW from dynamic-rules.sh
│   ├── memory-discipline.md    # NEW from dynamic-rules.sh
│   ├── memory-enforcement.md   # NEW from enforce-memory-preferences.sh
│   └── session-orientation.md  # NEW from inject-session-context.sh
├── agents/                     # Unchanged structure, fix test-writer
│   ├── architect.md
│   ├── code-reviewer.md
│   ├── researcher.md
│   └── test-writer.md          # Fixed: add disallowedTools
├── agent-mesh/                 # Unchanged
├── codebase-pilot/             # Unchanged
├── task-system/                # Unchanged
├── telemetry-worker/           # Unchanged
└── .claude-plugin/
    └── plugin.json             # Version bumped
```

---

## 6. Migration Risk Assessment

| Change | Risk | Impact | Mitigation |
|--------|------|--------|------------|
| Move 8 skills to commands/ | **Medium** | User-facing slash commands change from `/claudetools:name` to `/project:name` or `/user:name` | Document migration path; both patterns work during transition |
| Slim hooks.json | **Medium** | Behavioral text stops being injected by hooks; must be in rules/ | Create rules BEFORE removing hooks; verify identical behavior |
| Fix compact/full variants | **Low** | 3 skills with broken SKILL.md get proper frontmatter | Only improves current broken state |
| Add frontmatter to codebase-navigation.md | **Low** | No behavior change — just adds `---` delimiters | Purely structural |
| Consolidate memory extraction pipeline | **Medium** | Reduces AI extraction from 3 calls to 1-2 | Test that consolidated version captures all memory types |
| Remove quality gate duplication | **Low** | Unifies validator logic | Existing validators already work; just changing call site |
| Add disallowedTools to test-writer | **Low** | Restricts test-writer from writing non-test files | Only tightens existing implicit constraint |
| Deduplicate rule content | **Low** | Removes ~6 lines from no-shortcuts.md | Content already exists in deterministic-over-ai.md |

---

## 7. Prioritized Action Plan

### Phase 1: Fix structural issues (no behavior change)
1. Add YAML frontmatter to `codebase-navigation.md` — **low risk, immediate**
2. Add `disallowedTools` to `test-writer.md` — **low risk, immediate**
3. Remove duplicate section from `no-shortcuts.md` — **low risk, immediate**
4. Standardize compact/full variants to single SKILL.md — **low risk**
5. Fix broken `tune-weights.sh` reference in train skill — **low risk**

### Phase 2: Create new rules from hooks
6. Create `rules/project-tooling.md` from `dynamic-rules.sh` — **medium risk**
7. Create `rules/memory-discipline.md` from `dynamic-rules.sh` — **low risk**
8. Create `rules/memory-enforcement.md` from `enforce-memory-preferences.sh` — **medium risk**
9. Create `rules/session-orientation.md` from `inject-session-context.sh` — **low risk**

### Phase 3: Migrate skills to commands
10. Create `plugin/commands/` directory — **low risk**
11. Convert 8 user-invoked skills to command format — **medium risk**
12. Remove migrated skill directories — **medium risk**

### Phase 4: Consolidate hooks
13. Remove worktree echo from `mesh-lifecycle.sh` — **low risk**
14. Refactor `enforce-task-quality.sh` to use validators — **low risk**
15. Consolidate memory extraction pipeline — **medium risk**
16. Evaluate and remove `validators/memory-deep.sh` if duplicate — **medium risk**

### Phase 5: Slim hooks.json
17. Remove hook entries for fully-migrated scripts — **medium risk**
18. Verify hooks.json under 150 lines — **low risk**

### Phase 6: Update manifests and verify
19. Update plugin.json and marketplace.json — **medium risk**
20. Run full test suite — **low risk**
21. Write changelog and migration notes — **low risk**
22. Sync to plugins/claudetools/ — **low risk**
