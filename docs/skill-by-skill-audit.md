# Five-Step Algorithm: Skill-by-Skill Audit

> For each of the 15 skills: Question → Delete → Simplify → Accelerate → Automate

---

## 1. codebase-explorer (11 files, 1,234 LOC)

**Question:** 10 scripts are thin wrappers around codebase-pilot CLI commands. Do all 10 add value, or are some just `node $CLI <command>` with no additional logic?

**Delete:**
- `change-impact.sh` (16 LOC) — wrapper that just calls `node $CLI change-impact`. No added logic. Delete and document as a direct CLI call in SKILL.md.
- `dead-code.sh` (23 LOC) — same pattern. Delete.
- `find-route.sh` (69 LOC) — thin wrapper. Keep only if it adds filtering beyond the CLI.

**Simplify:** The 7 remaining scripts (security-scan, complexity-report, diff-schema, call-chain, trace-field, find-queries, full-audit) add real logic (formatting, filtering, multi-step analysis). Keep but document which are thin wrappers vs value-add in SKILL.md.

**Accelerate:** SKILL.md is 274 lines — good size. Trigger patterns are clear. No changes needed.

**Automate:** No tests exist. Add basic smoke tests for the 3 largest scripts (security-scan, complexity-report, diff-schema).

| Action | Files | LOC saved |
|--------|-------|-----------|
| Delete thin wrappers | change-impact.sh, dead-code.sh | ~39 |
| Document CLI commands | SKILL.md update | 0 |

---

## 2. claude-code-guide (14 files, 3,726 LOC)

**Question:** This is a reference library (8 guides) + 5 validation scripts. The guides are excellent. But the 5 validate-*.sh scripts (total 899 LOC) each implement their own pass/fail/warn output format with no shared framework.

**Delete:** Nothing — all content is reference material that's actively useful.

**Simplify:** Extract the common validation pattern from the 5 scripts into a shared `lib/validator-framework.sh`:
- `pass()`, `fail()`, `warn()` formatting
- Section header/footer
- Summary statistics
- Exit code logic

Each validate script currently reimplements these (~30 LOC each × 5 = 150 LOC of duplication).

**Accelerate:** No changes — reference files load on-demand, not at startup.

**Automate:** No tests. The validation scripts ARE test tools — but they themselves aren't tested. Add smoke tests that run each validator against a known-good and known-bad example.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Extract validator framework | Create lib/validator-framework.sh | ~120 saved |

---

## 3. code-review (4 files, 126 LOC)

**Question:** Is this skill distinct from the superpowers `requesting-code-review` skill? Yes — this is a structured 4-pass review process, superpowers is about preparing review context. They complement.

**Delete:** Nothing — minimal, focused, well-structured.

**Simplify:** `gather-diff.sh` (32 LOC) is solid. `review-checklist.md` (38 LOC) is concise. No simplification needed.

**Accelerate:** No changes.

**Automate:** Has test coverage already. No action.

| Action | Files | LOC saved |
|--------|-------|-----------|
| None | — | 0 |

---

## 4. debugger (3 files, 158 LOC)

**Question:** Minimal, focused, well-designed. Uses HARD GATE pattern ("NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST"). This is the gold standard for skill design.

**Delete:** Nothing.

**Simplify:** Already simple. 97-line SKILL.md with clear protocol steps.

**Accelerate:** No changes.

**Automate:** Has test coverage. No action.

| Action | Files | LOC saved |
|--------|-------|-----------|
| None — exemplar skill | — | 0 |

---

## 5. docs-manager (5 files, 223 LOC)

**Question:** `docs-reindex.sh` is 7 LOC — just calls `find` and generates markdown. Is this a script or a one-liner?

**Delete:**
- `docs-reindex.sh` (7 LOC) — inline into SKILL.md as a command example. Not worth a separate script.

**Simplify:** `docs-audit.sh` (96 LOC) and `docs-archive.sh` (49 LOC) are real scripts with logic. Keep.

**Accelerate:** SKILL.md is only 27 lines — expand with examples of when to use each command. Currently too sparse for agent self-discovery.

**Automate:** No tests. Low priority since scripts are simple.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Inline docs-reindex.sh | Delete script, add to SKILL.md | ~7 |
| Expand SKILL.md | Add usage examples | 0 |

---

## 6. field-review (3 files, 283 LOC)

**Question:** `collect-metrics.sh` (191 LOC) overlaps with the new `lib/health-report.sh` (95 LOC) created in Phase 5. Both query metrics.db for hook outcomes and validator health. Are both needed?

**Delete:**
- Merge `collect-metrics.sh` logic into `lib/health-report.sh`. The health-report library is the canonical location for metrics queries. The skill should call the library, not duplicate it.

**Simplify:** `submit-feedback.sh` (62 LOC) posts feedback to telemetry endpoint. Keep as-is — distinct from metrics collection.

**Accelerate:** No changes.

**Automate:** No tests. After merging, add tests for `lib/health-report.sh` (covers both use cases).

| Action | Files | LOC saved |
|--------|-------|-----------|
| Merge collect-metrics into health-report | Rewrite collect-metrics.sh to call lib | ~140 |

---

## 7. frontend-design (34 files, 7,484 LOC)

**Question:** This is the largest skill by far. 6 Python scripts (2,332 LOC), 6 shell scripts (1,012 LOC), 16 reference files (2,348 LOC), 4 asset templates (872 LOC), SKILL.md (455 LOC). Does every component justify its existence?

**Delete:**
- `scripts/.gitignore` (1 LOC) — empty, delete.
- Check if `scripts/.deps/` (package.json, package-lock.json) is needed or leftover build artifact. If leftover, delete.

**Simplify:**
- SKILL.md at 455 lines is the longest of any skill. Per prompting guide, >200 lines reduces adherence. Split into:
  - `SKILL.md` (~200 lines) — core workflow (detect project, choose mode, build/maintain)
  - `references/craft-checks.md` — the squint/swap/signature tests
  - `references/token-system.md` — merge `token-naming.md` into this
- `audit-design.py` (808 LOC) is enormous for a skill script. Verify it's all needed — Python files this large often have dead code.

**Accelerate:** The Python scripts require `PIL`, `sklearn` — heavy deps. Add a dependency check at the top of each script that exits gracefully with a useful message if deps are missing.

**Automate:** Zero tests for 7,484 LOC. This is the highest-risk skill. At minimum, add smoke tests for `scaffold-project.sh` and `validate-design.sh`.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Split SKILL.md | Extract craft checks + tokens to refs | ~150 (from SKILL.md) |
| Delete .gitignore | 1 file | 1 |
| Add dep checks to Python scripts | 6 scripts | 0 (adds ~30) |

---

## 8. logs (8 files, 1,873 LOC)

**Question:** `session_common.py` (651 LOC) is a massive shared Python library. `logs.sh` (489 LOC) is a bash entry point. This skill is really a log analysis toolkit. Is it a user skill or internal tooling?

**Delete:**
- `scripts/lib/__init__.py` (0 LOC) — empty Python init. Keep for package structure (required by Python imports).

**Simplify:**
- `logs.sh` (489 LOC) does too much — it's a CLI router with subcommands (search, extract, analyze, compare). Split into the individual scripts it already calls. The SKILL.md should list the subcommands directly rather than routing through a monolithic bash script.
- `session_common.py` (651 LOC) — audit for dead code. A 651-line shared library in a skill is unusual. Check if all functions are actually called.

**Accelerate:** No changes to speed.

**Automate:** No tests. Add basic smoke tests for `logs.sh` subcommands.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Audit session_common.py for dead code | 1 file | TBD |
| Consider splitting logs.sh | 1 file | 0 (restructure) |

---

## 9. memory (7 files, 791 LOC)

**Question:** This skill has 2 Python scripts (validate_memory.py, memory_stats.py) and 3 reference docs. The plugin also has `memory-combined.sh`, `memory-index.sh`, `memory-consolidate.sh` in scripts/. Is the skill the right entry point, or is it disconnected from the hook-level memory system?

**Delete:** Nothing — the Python scripts serve a distinct purpose (validation, statistics) from the hook scripts (extraction, indexing).

**Simplify:** The 3 references (setup-guide, memory-schema, application-rules) total 371 LOC. These are well-structured. No changes.

**Accelerate:** `validate_memory.py` (180 LOC) checks memory file health. This could be called from the session-dashboard health report. Wire it in.

**Automate:** No tests. Add smoke test for `validate_memory.py`.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Wire validate_memory into health report | 1 integration | 0 |

---

## 10. plugin-improver (4 files, 761 LOC)

**Question:** `collect-all-data.sh` (301 LOC) gathers telemetry, memory, and web data for improvement analysis. `capture-snapshot.sh` (114 LOC) saves baseline metrics. `log-improvement.sh` (101 LOC) records what was changed. All three are mentioned in SKILL.md's workflow. But SKILL.md doesn't list `collect-all-data.sh` or `log-improvement.sh` in its scripts section.

**Delete:** Nothing — all scripts serve the workflow.

**Simplify:** Fix SKILL.md to list all 3 scripts with descriptions. Currently incomplete.

**Accelerate:** `collect-all-data.sh` could use `lib/health-report.sh` for the metrics portion instead of reimplementing queries.

**Automate:** No tests. The skill is self-improving — but it itself isn't tested. Add smoke test.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Update SKILL.md with all scripts | SKILL.md | 0 |
| Use health-report.sh in collect-all-data | 1 file | ~50 |

---

## 11. prompt-improver (8 files, 2,353 LOC)

**Question:** Well-structured skill. `gather-context.sh` (325 LOC) + `validate-prompt.sh` (215 LOC) are substantial. 3 reference docs (983 LOC) cover principles, XML templates, and chaining. The `before-after.md` examples file (489 LOC) is the largest component.

**Delete:** Nothing — examples are the strongest signal for AI agents (per prompting guide). 489 LOC of examples is justified.

**Simplify:** SKILL.md at 320 lines is slightly over the 200-line target but well-structured. No split needed — the modes (execute/plan/task) are all essential.

**Accelerate:** No changes.

**Automate:** Has test coverage. No action.

| Action | Files | LOC saved |
|--------|-------|-----------|
| None — well-designed | — | 0 |

---

## 12. safety-evaluator (1 file, 280 LOC)

**Question:** Single-file skill — the entire training framework is in SKILL.md. It uses `TeamCreate` to dispatch parallel training scenarios. Does this need any scripts?

**Delete:** Nothing.

**Simplify:** The 280-line SKILL.md is dense but well-structured. It uses `disable-model-invocation: true` for deterministic execution. No changes.

**Accelerate:** No changes.

**Automate:** The skill IS the automation (it runs training scenarios). No meta-automation needed.

| Action | Files | LOC saved |
|--------|-------|-----------|
| None — focused single-file skill | — | 0 |

---

## 13. session-dashboard (2 files, 126 LOC)

**Question:** `generate-report.sh` (91 LOC) now includes the health report integration from Phase 5. Is this enough, or should the dashboard be richer?

**Delete:** Nothing.

**Simplify:** Already minimal. No changes.

**Accelerate:** The health report queries could be slow on large metrics.db. Add `LIMIT` clauses to SQL queries if not present.

**Automate:** Has test coverage. No action.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Add LIMIT to SQL queries | generate-report.sh | 0 |

---

## 14. statusline (1 file, 57 LOC)

**Question:** File is named `skill.md` (lowercase) — inconsistent with all other skills that use `SKILL.md`.

**Delete:** Nothing.

**Simplify:** Rename `skill.md` → `SKILL.md` for consistency.

**Accelerate:** No changes.

**Automate:** No tests needed — config-only skill.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Rename skill.md → SKILL.md | 1 file | 0 |

---

## 15. task-manager (8 files, 1,148 LOC)

**Question:** Uses JavaScript for 3 scripts (validate-tasks.js 263 LOC, task-report.js 247 LOC, sync-display.js 58 LOC) — the only skill using JS besides the (now deleted) on-todo-write.js. Is JS necessary here, or could these be bash?

**Delete:**
- `sync-display.js` (58 LOC) — undocumented, not referenced in SKILL.md. Check if it's called by any hook. If not, delete.

**Simplify:**
- The JS scripts read `.tasks/tasks.json` and `.tasks/history.jsonl`. This is the same data the MCP task-system server manages. Are these scripts duplicating the MCP server's capabilities? If yes, the skill should call the MCP tools instead of reimplementing JSON parsing.
- SKILL.md at 342 lines is over the 200-line target. Split references into separate files.

**Accelerate:** No changes.

**Automate:** No tests. Add basic smoke tests for validate-tasks.js.

| Action | Files | LOC saved |
|--------|-------|-----------|
| Delete sync-display.js if unused | 1 file | ~58 |
| Check JS/MCP duplication | 2 files | TBD |
| Split SKILL.md references | SKILL.md | 0 (restructure) |

---

## Summary: Priority Actions

### High Priority (fix now)

| Skill | Action | LOC impact |
|-------|--------|-----------|
| **statusline** | Rename skill.md → SKILL.md | 0 |
| **field-review** | Merge collect-metrics.sh into lib/health-report.sh | -140 |
| **codebase-explorer** | Delete 2 thin wrappers (change-impact, dead-code) | -39 |
| **claude-code-guide** | Extract shared validator framework from 5 scripts | -120 |
| **plugin-improver** | Update SKILL.md to list all scripts | 0 |

### Medium Priority (next session)

| Skill | Action | LOC impact |
|-------|--------|-----------|
| **frontend-design** | Split SKILL.md (455→~200), add Python dep checks | -150 |
| **task-manager** | Delete sync-display.js if unused, check MCP overlap | -58 |
| **docs-manager** | Inline docs-reindex.sh (7 LOC), expand SKILL.md | -7 |
| **logs** | Audit session_common.py (651 LOC) for dead code | TBD |

### Low Priority (backlog)

| Skill | Action | LOC impact |
|-------|--------|-----------|
| **memory** | Wire validate_memory.py into health report | 0 |
| **plugin-improver** | Use health-report.sh in collect-all-data.sh | -50 |
| **session-dashboard** | Add LIMIT to SQL queries | 0 |

### No Changes Needed

| Skill | Reason |
|-------|--------|
| **debugger** | Exemplar — gold standard skill design |
| **code-review** | Minimal, focused, tested |
| **prompt-improver** | Well-structured, tested, good examples |
| **safety-evaluator** | Focused single-file skill, deterministic |

---

## Total Impact

| Metric | Current | After |
|--------|---------|-------|
| Total skill LOC | 21,444 | ~20,800 (-644) |
| Thin wrapper scripts | 3 | 0 |
| Duplicated validator framework | 5 copies | 1 shared lib |
| Skills with inconsistent naming | 1 | 0 |
| SKILL.md files >200 lines | 3 | 1 (safety-evaluator at 280, justified) |
| Metrics collection duplication | 2 implementations | 1 (health-report.sh) |
