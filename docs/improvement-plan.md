# Claudetools Plugin: Comprehensive Improvement Plan

> Applying the Five-Step Algorithm, Intelligence Spectrum, and superpowers design principles to every layer of the plugin.

---

## Current State

| Layer | Components | LOC | Health |
|-------|-----------|-----|--------|
| **Hooks** | 47 scripts, 16 event types | 4,200 | Refactored (this session) |
| **Validators** | 26 scripts, 8 dispatchers | 3,200 | Needs consolidation |
| **Skills** | 15 directories (7 undocumented) | 18,400 | 47% undiscoverable |
| **Libraries** | 13 shared libs | 1,300 | Clean, well-partitioned |
| **Codebase-pilot** | 8 TS files, tree-sitter | 428 KB | 30s startup cost |
| **Task system** | MCP server + 2 JS libs | 300 | Dual-track (TodoWrite + native) |
| **Agent mesh** | 1 CLI, zero deps | 20 KB | Clean |
| **Database** | 8 active tables, 3 dormant | 385 (schema) | Training tables unused |
| **Telemetry** | JSONL + optional remote | 250 | Working, optional upload |

**Total: ~27,000 LOC across ~143 files**

---

## Step 1: QUESTION — What shouldn't exist?

### Skills: 7 undocumented = undiscoverable = dead

| Skill | LOC | Issue | Verdict |
|-------|-----|-------|---------|
| `claude-code-guide` | 6,982 | No SKILL.md. Largest skill, zero discoverability. | **ADD SKILL.md** or merge into codebase-explorer |
| `code-review` | 180 | No SKILL.md. Unclear if active. | **ADD SKILL.md** or delete |
| `docs-manager` | 392 | No SKILL.md. 4 scripts with no workflow. | **ADD SKILL.md** or fold into hooks |
| `field-review` | 506 | No SKILL.md. Purpose unclear. | **ADD SKILL.md** or delete |
| `logs` | 3,690 | No SKILL.md. 5 Python utilities. | **RECLASSIFY** as internal tooling, not a skill |
| `memory` | 1,444 | No SKILL.md. Python memory utilities. | **RECLASSIFY** as internal tooling |
| `session-dashboard` | 83 | No SKILL.md. Single script. | **ADD SKILL.md** (quick win) |

**Question:** Is 6,982 LOC of `claude-code-guide` justified when `codebase-explorer` (2,668 LOC) covers the same territory? If claude-code-guide is plugin-development-specific and codebase-explorer is general-purpose, they're distinct. If they overlap, merge.

### Validators: 8 compensate for missing process

Per the system audit, these validators exist because skills don't enforce upstream constraints:

| Validator | LOC | Compensates for | Could be prevented by |
|-----------|-----|----------------|----------------------|
| `blind-edit.sh` | 100 | No read-before-write process | Skill workflow: always read first |
| `task-scope.sh` | 100 | No upfront planning | Planning skill: acceptance criteria define scope |
| `unasked-deps.sh` | 98 | No dependency approval | Planning skill: deps approved in plan |
| `unasked-restructure.sh` | 94 | No restructuring approval | Planning skill: structure changes in plan |
| `prefer-edit-over-write.sh` | 60 | No tool-selection process | Skill instruction: prefer Edit |
| `no-deferred-actions.sh` | 80 | No completion criteria | Verification skill: must complete, not defer |
| `ran-checks.sh` | 80 | No TDD/verification | TDD skill: tests run before completion |
| `bulk-edit.sh` | 80 | No bulk-operation process | Skill instruction: use sed for bulk |

**Total: 692 LOC of reactive enforcement that proactive skills could eliminate.**

### Database: 3 dormant training tables

Tables `reference_codebases`, `prompt_chains`, `chain_steps`, `chain_executions`, `step_executions`, `deviations`, `guardrail_gaps` are schema-only — never populated, never queried.

**Verdict:** Move training schema to a separate `training.db` created on-demand by the safety-evaluator skill. Keeps metrics.db focused.

### Task system: dual-track confusion

- Track 1: TodoWrite → `on-todo-write.js` → `.tasks/tasks.json`
- Track 2: Native TaskCreate/TaskUpdate → `track-native-tasks.sh`

Two systems tracking the same concept. Native tasks are the primary mechanism.

**Verdict:** Drop TodoWrite track. Remove `on-todo-write.js` hook entry. ~230 LOC saved + one Node.js dependency removed.

---

## Step 2: DELETE

### Phase A: Delete dead/dormant code

| Target | LOC saved | Risk |
|--------|----------|------|
| Remove `logs/` from skills (reclassify as tooling) | 3,690 (reclassify) | LOW — no SKILL.md, never invoked as skill |
| Remove `memory/` from skills (reclassify as tooling) | 1,444 (reclassify) | LOW — same |
| Remove TodoWrite hook + `on-todo-write.js` | 230 | MEDIUM — verify no workflows depend on it |
| Remove training tables from `ensure-db.sh` | 80 | LOW — never populated |
| Remove `session-wrap.sh` validator | 140 | MEDIUM — spawns `claude --resume` unreliably (P0 bug) |

### Phase B: Downgrade compensatory validators

Don't delete yet — downgrade from block to warn, then track trigger rates. If trigger rate drops to near-zero after skill improvements, delete.

| Validator | Current | Downgrade to | Condition to delete |
|-----------|---------|-------------|-------------------|
| `blind-edit.sh` | warn | keep as warn | Delete when read-before-write is in skill workflows |
| `task-scope.sh` | warn | keep as warn | Delete when planning skill enforces scope |
| `unasked-deps.sh` | warn | keep as warn | Delete when planning skill covers deps |
| `prefer-edit-over-write.sh` | warn | keep as warn | Delete when tool routing is in skill instructions |
| `no-deferred-actions.sh` | block | downgrade to warn | High false-positive rate (25%) |
| `bulk-edit.sh` | block | downgrade to warn | Workflow issue, not safety |

### Phase C: Fix P0 bugs found in audit

1. **PPID collision in `aggregate-session.sh` and `deploy-loop-detector.sh`** — Use `$SESSION_ID` instead of `$PPID` for log filenames. Multiple agents sharing PPID causes false "deploy loop" warnings.
2. **`session-wrap.sh` async spawn fragility** — Spawns `claude --resume` without confirming transcript exists. Either add retry or delete entirely (see Phase A).

---

## Step 3: SIMPLIFY

### A. Make skills mandatory (superpowers pattern)

The highest-impact change. Currently, claudetools skills are optional. Superpowers makes them non-negotiable.

**Implementation:** Strengthen `UserPromptSubmit: inject-prompt-context.sh` to:

1. Classify user intent via Tier 1 keyword matching:
   - `build|create|implement|add feature` → brainstorming + planning skill
   - `fix|debug|broken|error|failing` → debugger skill
   - `review|audit|check` → code-review skill
   - `deploy|publish|release` → deployment checklist
2. Inject matched skill instructions into context (same as superpowers' SessionStart injection)
3. Include a HARD GATE: "Do NOT write code until you have followed the skill's process"

This shifts the plugin from reactive enforcement to proactive constraint — the superpowers principle.

### B. Consolidate skill documentation

7 skills have no SKILL.md. For each:

| Skill | Action | Effort |
|-------|--------|--------|
| `claude-code-guide` | Add SKILL.md with trigger: "how to build plugins, hooks, skills, MCP servers" | 1 hour |
| `code-review` | Add SKILL.md with trigger: "review code, audit, check quality" | 30 min |
| `docs-manager` | Add SKILL.md with trigger: "manage docs, generate index, audit docs" | 30 min |
| `field-review` | Add SKILL.md with trigger: "field review, evaluate hooks, report on plugin health" | 30 min |
| `session-dashboard` | Add SKILL.md with trigger: "session stats, health report, metrics" | 15 min |
| `logs` | Move to `scripts/lib/log-tools/` (internal utility, not a user skill) | 1 hour |
| `memory` | Move to `scripts/lib/memory-tools/` (internal utility, not a user skill) | 1 hour |

### C. Simplify the memory system

Current: 3 levels (FTS index → deterministic extraction → AI reflection)

Proposed: 2 levels
- **Level 1 (FTS index):** Keep as-is. Deterministic, fast, always runs.
- **Level 2 (combined extract + reflect):** Merge `memory-extract-fast.sh` and `memory-reflect.sh` into one async hook:
  1. Run deterministic extraction (grep-based, <1s)
  2. Save extracted candidates immediately (never lost to timeout)
  3. If high-signal candidates found AND session was substantial, invoke AI reflection
  4. AI reflection is additive — extraction already saved even if AI times out

This ensures the deterministic extraction is never lost and reduces hook count from 2 to 1.

### D. Simplify the database

Current: 8 active tables + 3 dormant training tables in one `metrics.db`

Proposed:
- **metrics.db:** `tool_outcomes`, `session_metrics`, `hook_outcomes`, `threshold_overrides`, `model_profiles`, `threshold_history` (6 tables — operational)
- **memory.db:** `memories`, `memories_fts`, `project_memories`, `memory_effectiveness` (4 tables — memory system)
- **training.db:** Created on-demand by safety-evaluator skill only

Splitting memory from metrics reduces contention and makes the memory system independently testable.

### E. Simplify codebase-pilot startup

Current: Full 30s index rebuild at every SessionStart.

Proposed:
1. Check if `.codeindex/db.sqlite` exists and was modified within the last hour
2. If yes: skip full index, run incremental update (changed files only via `git diff`)
3. If no: full rebuild (still 30s, but only on first session or after long gap)
4. Register a ConfigChange hook to trigger full rebuild when project config changes

Expected: SessionStart drops from 60s to ~10s for returning sessions.

---

## Step 4: ACCELERATE

### A. Tier 1 routing at the dispatcher level

Currently, every PreToolUse matcher runs its full validator chain. Apply Intelligence Spectrum routing:

```
PreToolUse:Bash
  → Tier 1: Is command in safe fast-path? → Allow (0ms) ✓ DONE
  → Tier 1: Is command in dangerous patterns? → Block (1ms)
  → Tier 2: Needs AI safety check? → Run ai-safety validator

PreToolUse:Edit/Write
  → Tier 1: Is file test/doc/config? → Skip content validators (0ms)
  → Tier 1: Is file sensitive (.env, .pem)? → Block (1ms)
  → Tier 2: Run remaining validators

PostToolUse:Edit/Write
  → Tier 1: Is file test/doc? → Skip stubs/secrets checks (0ms)
  → Tier 2: Run content validators
```

The fast-path for `dangerous-bash.sh` is already done. Apply the same pattern to other dispatchers.

### B. Cache git state per tool-use cycle

`lib/git-state.sh` caches via exports — but exports are per-process. For PostToolUse validators that run in the same dispatcher process, caching works. For PreToolUse hooks that each run as separate processes, caching doesn't help.

**Optimization:** Write git state to a session-scoped temp file at SessionStart, refresh on file edits:
```
/tmp/claude-git-state-${SESSION_ID}.json
{
  "is_repo": true,
  "branch": "feat/my-feature",
  "changed_files": ["src/foo.ts", "src/bar.ts"],
  "timestamp": 1711900000
}
```

Validators read this file instead of forking git. Refresh after every Edit/Write PostToolUse.

### C. Lazy-load codebase-pilot

Currently `pilot-query.sh` ensures the index on every call. Instead:
1. At SessionStart, set `PILOT_INDEX_READY=1` in the session temp file
2. `pilot-query.sh` checks this flag — if set, skip ensure_index
3. Only re-ensure on ConfigChange or if flag is missing

---

## Step 5: AUTOMATE

### A. Automate skill discovery and invocation

Build a Tier 1 intent classifier (keyword matching, zero tokens) that maps user prompts to skills:

```bash
# In inject-prompt-context.sh (UserPromptSubmit hook)
case "$USER_PROMPT" in
  *build*|*create*|*implement*|*add*feature*)
    inject_skill "brainstorming" ;;
  *fix*|*debug*|*broken*|*error*|*failing*)
    inject_skill "debugger" ;;
  *review*|*audit*|*check*quality*)
    inject_skill "code-review" ;;
  *deploy*|*publish*|*release*)
    inject_skill "deployment-checklist" ;;
  *explore*|*find*|*where*is*|*trace*)
    inject_skill "codebase-explorer" ;;
esac
```

This is the superpowers pattern: mandatory skill invocation based on intent, not optional discovery.

### B. Automate validator health tracking

After all changes, the remaining validators are genuine safety gates. Track their effectiveness:

1. Record every block/warn/allow decision (already done via `record_hook_outcome`)
2. Add a weekly summary query: false positive rate = (user overrides block) / (total blocks)
3. If a validator has >50% false positive rate over 30 days, flag for review
4. If a validator has 0% trigger rate over 30 days, flag as potentially dead

Implement as a `plugin-improver` skill enhancement — it already has a "baseline measurement" phase.

### C. Automate stale skill detection

Track skill invocations in telemetry (currently not tracked). Add `emit_event "skill_invocation" "$skill_name"` to the skill loading mechanism. Skills with zero invocations over 30 days are candidates for deletion or documentation improvement.

---

## Implementation Phases

### Phase 1: Quick Wins (1 session)
- [ ] Fix P0 bugs (PPID collision, session-wrap fragility)
- [ ] Add SKILL.md to 5 undocumented skills
- [ ] Reclassify `logs/` and `memory/` as internal tooling
- [ ] Downgrade `no-deferred-actions.sh` from block to warn
- [ ] Remove training tables from ensure-db.sh

### Phase 2: Skills as Constraints (2-3 sessions)
- [ ] Strengthen `inject-prompt-context.sh` with intent classification
- [ ] Add HARD GATES to implementation-related skills
- [ ] Test with real sessions — measure validator trigger rates before/after
- [ ] Merge memory hooks (extract-fast + reflect → single async hook)

### Phase 3: Performance (1-2 sessions)
- [ ] Make codebase-pilot incremental (skip full rebuild for returning sessions)
- [ ] Add Tier 1 routing to Edit/Write dispatchers
- [ ] Cache git state in session temp file
- [ ] Lazy-load codebase-pilot index

### Phase 4: Cleanup (1 session)
- [ ] Remove TodoWrite track (on-todo-write.js + hook entry)
- [ ] Split memory tables to memory.db
- [ ] Delete compensatory validators with near-zero trigger rates
- [ ] Add validator health tracking query

### Phase 5: Automate (1 session)
- [ ] Add skill invocation telemetry
- [ ] Implement stale skill detection
- [ ] Add false-positive rate tracking for validators
- [ ] Update plugin-improver skill with new baseline metrics

---

## Expected Outcome

| Metric | Current | After |
|--------|---------|-------|
| **SessionStart** | 60s | <10s (returning sessions) |
| **Skills discoverable** | 8/15 (53%) | 13/13 (100%) — 2 reclassified |
| **Validators** | 26 | 18-20 (compensatory ones removed) |
| **Memory hooks** | 3 | 2 (extract + reflect merged) |
| **Task tracks** | 2 | 1 (native only) |
| **DB tables** | 11 (3 dormant) | 6 operational + 4 memory (separate DB) |
| **Hook philosophy** | Reactive enforcement | Proactive constraints + safety gates |
| **Validator LOC** | 3,200 | ~2,400 |
| **False positive tracking** | None | Automated weekly |

The end state: a plugin that **prevents problems through mandatory skill workflows** (like superpowers) while maintaining **genuine safety gates** (secrets, dangerous commands, file access) as a deterministic safety net. Skills handle process. Validators handle safety. Nothing else.
