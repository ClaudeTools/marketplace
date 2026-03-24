---
title: "Common Recipes"
description: "12 composite workflows showing how claudetools features work together — from debug-and-fix to multi-agent parallel work."
---

**Difficulty: Intermediate**

Real situations rarely fit a single tool. These recipes show how skills, agents, hooks, and commands compose into end-to-end workflows.

---
**Difficulty: Intermediate**


## 1. Debug and fix a production bug

**Goal:** Reproduce, fix, and verify a reported bug — with code review before commit.

**Commands used:**
- `/claudetools:investigating-bugs` — structured 6-step debugging protocol
- `/claudetools:code-reviewer` — read-only quality review of the fix
- `/commit` — conventional commit after review passes

**Workflow:**

1. `"The payment endpoint returns 500 when the order total is zero"` — investigating-bugs activates automatically from "500" and "returns".
2. Claude works through REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY, identifying the zero-division in `calculateTax()`.
3. Claude fixes the file. The `validate-content` hook checks the change for stubs or type escapes.
4. `"/code-review src/services/payment.ts"` — 4-pass review flags any missed edge cases.
5. Fix the findings, then `/commit` with a `fix:` message.

**What happens behind the scenes:**

- `pre-edit-gate.sh` blocks the edit if Claude hasn't read the file first.
- `validate-content.sh` fires PostToolUse to catch stub implementations.
- `post-agent-gate.sh` verifies the code-reviewer actually completed its review passes.

---
**Difficulty: Intermediate**


## 2. Explore and document unfamiliar code

**Goal:** Build a mental model of an unknown codebase and produce navigable documentation.

**Commands used:**
- `/claudetools:exploring-codebase` — semantic navigation via codebase-pilot
- `codebase-pilot map` — project overview to start
- `/claudetools:docs-manager` — create and index the output

**Workflow:**

1. `"Map the project and explain how authentication works"` — exploring-codebase activates.
2. Claude runs `codebase-pilot map` to get the project layout, then `find-symbol AuthService` to locate the entry point.
3. Claude traces the import graph with `related-files` and builds a call tree from `login()` to token issuance.
4. `"/docs-manager init"` — sets up the docs structure if missing.
5. Claude writes the architecture doc; `doc-manager.sh` enforces kebab-case naming and YAML frontmatter.

**What happens behind the scenes:**

- `enforce-codebase-pilot.sh` redirects any grep attempts to the semantic index instead.
- `doc-manager.sh` (PostToolUse on Write) auto-updates the `modified` field in frontmatter.
- `doc-index-generator.sh` (SessionEnd) regenerates the docs index automatically.

---
**Difficulty: Intermediate**


## 3. Safe multi-file refactor

**Goal:** Refactor a shared module without breaking callers — with automated impact analysis and regression checking.

**Commands used:**
- `codebase-pilot change-impact` — find everything that would break
- `/claudetools:refactor-pipeline` — orchestrated impact → implement → verify flow
- `/claudetools:code-reviewer` — post-refactor review

**Workflow:**

1. `"I want to rename UserService to AccountService and update all callers"` — refactor-pipeline agent spawns.
2. Agent runs `codebase-pilot change-impact UserService` — finds 14 callers across 8 files.
3. Agent decomposes the work into per-file tasks and implements changes in dependency order.
4. Typecheck runs after each file (`npx tsc --noEmit`). Any failure halts the sequence.
5. `/code-review` runs on the full diff before commit.

**What happens behind the scenes:**

- `edit-frequency-guard.sh` warns if any single file is edited more than 3 times (trial-and-error signal).
- `enforce-team-usage.sh` requires the agent to use `TeamCreate` for parallel sub-work.
- `verify-subagent-independently.sh` (SubagentStop) re-runs typecheck independently of the agent's self-report.

---
**Difficulty: Intermediate**


## 4. Build a feature with tests

**Goal:** Implement a new feature end-to-end — from task creation through implementation, tests, and review.

**Commands used:**
- `/claudetools:managing-tasks` — create and track the task
- `/claudetools:feature-pipeline` — explore → plan → implement → review → verify
- `/claudetools:test-writer` — generate coverage for the new code

**Workflow:**

1. `"/managing-tasks new Add rate limiting to the API"` — task created with codebase context enrichment.
2. `"Spawn feature-pipeline for task-a4f2"` — pipeline agent explores existing middleware, plans the implementation, then executes.
3. Pipeline completes implementation. `/claudetools:test-writer` generates targeted tests matching existing patterns.
4. Tests pass; `/code-review` runs the 4-pass review.
5. `/commit` with `feat:` prefix. Task marked completed automatically.

**What happens behind the scenes:**

- `require-active-task.sh` blocks any file write unless there's an active task.
- `post-agent-gate.sh` checks that the feature-pipeline actually completed all subtasks.
- `capture-outcome.sh` records the session metrics (tool calls, failures, churn) to `metrics.db`.

---
**Difficulty: Intermediate**


## 5. Security audit and remediation

**Goal:** Find security vulnerabilities, fix critical findings, and re-audit to confirm resolution.

**Commands used:**
- `/claudetools:security-pipeline` — read-only full-codebase security audit
- `/claudetools:investigating-bugs` — for each critical finding
- `/claudetools:code-reviewer` — verify fixes before commit

**Workflow:**

1. `"/claudetools:security-pipeline"` — agent runs audit, dep scan, and dead-code analysis. No files are modified.
2. Review the structured findings report (Critical / Important / Suggestions).
3. For each Critical finding: `"Fix the SQL injection in orders.ts:84"` — investigating-bugs activates to trace the root cause.
4. Claude applies the fix. `validate-content.sh` checks for new stubs introduced during the fix.
5. Re-run `"/claudetools:security-pipeline"` on the affected files to confirm the finding is resolved.

**What happens behind the scenes:**

- Security-pipeline has `disallowedTools: [Edit, Write]` — it physically cannot modify files.
- `guard-sensitive-files.sh` blocks reads to `.env` and credential files during audit traversal.
- `block-dangerous-bash.sh` intercepts any shell commands that resemble exfiltration patterns.

---
**Difficulty: Intermediate**


## 6. Set up a new project

**Goal:** Bootstrap Claude Code configuration, codebase-pilot indexing, and initial CLAUDE.md for a new repo.

**Commands used:**
- `/claudetools:setup-new-project` (via prompt-improver or directly)
- `codebase-pilot index` — build the semantic index
- `/claudetools:claude-md-improver` — audit and improve project instructions

**Workflow:**

1. Clone the repo and open it in Claude Code.
2. `"Set up this project for Claude Code development"` — setup-new-project skill activates.
3. Claude detects the project type (`detect-project.sh`) and writes project-appropriate CLAUDE.md with build/test/lint commands.
4. `codebase-pilot index` — builds the SQLite symbol index. First run takes 10-30 seconds.
5. `"/claudetools:claude-md-improver"` — audits the generated CLAUDE.md against quality templates and improves it.

**What happens behind the scenes:**

- `inject-session-context.sh` (SessionStart) will begin injecting learned patterns once the metrics DB has a few sessions.
- `doc-stale-detector.sh` (SessionStart) watches for docs older than 90 days going forward.
- `config-audit-trail.sh` logs the initial configuration to a JSONL audit trail.

---
**Difficulty: Intermediate**


## 7. Multi-agent parallel work

**Goal:** Split a large task across multiple agents working in parallel, coordinated via the mesh.

**Commands used:**
- `/claudetools:mesh` — check who's active, lock files, share decisions
- `TeamCreate` — spawn coordinated agent teammates
- `/claudetools:managing-tasks` — decompose and assign subtasks

**Workflow:**

1. `"/mesh status"` — check no other agents are working on conflicting files.
2. `"/managing-tasks new Migrate all API routes to the new auth middleware"` — decompose into per-route subtasks.
3. Spawn teammates: `TeamCreate` with agents assigned to separate route files.
4. Each agent checks `/mesh who --file <path>` before editing — mesh prevents concurrent edits to the same file.
5. Agents message each other when dependencies are ready: `/mesh send agent-2 "auth-middleware.ts is ready"`.

**What happens behind the scenes:**

- `enforce-team-usage.sh` blocks bare `Agent` spawning — `TeamCreate` is required for coordinated work.
- `mesh-lifecycle.sh` (WorktreeCreate) registers each new agent with the mesh on startup.
- `TeammateIdle` hooks fire when any agent goes idle, triggering status updates to the team lead.

---
**Difficulty: Intermediate**


## 8. Improve a vague prompt

**Goal:** Turn a rough idea into a structured, executable task with guardrails burned in.

**Commands used:**
- `/claudetools:prompt-improver` — structured XML prompt generation
- The improved prompt — then execute directly

**Workflow:**

1. `"Refactor the database layer"` — too vague; run `/prompt-improver "Refactor the database layer"`.
2. Prompt-improver asks 2-3 clarifying questions: scope, target pattern, what "done" looks like.
3. Claude generates a structured XML prompt with approach blocks, escape clauses, and acceptance criteria.
4. Review the improved prompt. Reply `"looks good"` to execute it, or `"show me the plan"` to review first.
5. The structured task executes with explicit success criteria — Claude stops when criteria are met.

**What happens behind the scenes:**

- `inject-prompt-context.sh` (UserPromptSubmit) enriches every submitted prompt with git state and active task before Claude sees it.
- `block-unasked-restructure.sh` prevents the improved prompt from triggering unrequested project-wide changes.
- `auto-approve-safe.sh` (PermissionRequest) approves read-only tools automatically so the prompt doesn't stall on permission prompts.

---
**Difficulty: Intermediate**


## 9. Review a pull request

**Goal:** Get a structured code review of a branch diff, fix findings, then re-review to confirm.

**Commands used:**
- `/code-review` — 4-pass structured review
- Fix cycle — address findings
- `/code-review` again — confirm resolution

**Workflow:**

1. `"/code-review feature/add-webhooks"` — review runs against the diff of that branch vs main.
2. Claude outputs findings grouped by severity: Critical / Important / Suggestions / Positive.
3. Address each Critical and Important finding. The `validate-content` hook checks each fix.
4. `"/code-review feature/add-webhooks"` — second pass. Only new or unresolved findings appear.
5. If Critical section is empty, the PR is ready to merge.

**What happens behind the scenes:**

- code-reviewer agent is read-only — it cannot accidentally modify files during review.
- `pre-edit-gate.sh` ensures any fixes during this session are made on read files only.
- `edit-frequency-guard.sh` warns if the same file is fixed more than 3 times (may signal a design problem).

---
**Difficulty: Intermediate**


## 10. Track complex work across sessions

**Goal:** Break down a large initiative into tracked tasks, hand off between sessions, and restore context cleanly.

**Commands used:**
- `/claudetools:managing-tasks` — create, decompose, and track
- `/session-dashboard` — health check at the start of each new session

**Workflow:**

1. `"/managing-tasks new Implement full-text search across all documents"` — decompose into subtasks.
2. Work through subtasks across multiple sessions. Each session: `"/session-dashboard"` shows what failed last time.
3. At session end, the managing-tasks skill generates a handoff summary with: tasks completed, tasks in progress, blockers, next recommended action.
4. Next session: `"/managing-tasks status"` restores context. Claude resumes from the correct task.
5. When the initiative is complete: `"/managing-tasks complete <parent-task-id>"`.

**What happens behind the scenes:**

- `inject-session-context.sh` (SessionStart) re-injects learned failure patterns from `metrics.db`.
- `archive-before-compact.sh` (PreCompact) saves critical task state before context is compressed.
- `restore-after-compact.sh` (PostCompact) re-injects the saved state after compaction.
- `session-stop-gate.sh` (Stop) runs a comprehensive review before exit, ensuring no tasks are left dangling.

---
**Difficulty: Intermediate**


## 11. Design a polished UI

**Goal:** Build a production-quality interface with design systems, responsive layout, and accessibility.

**Commands used:**
- `/claudetools:frontend-design` — high-quality UI generation with design principles
- Iterate — refine with targeted follow-up prompts

**Workflow:**

1. `"Build a dashboard for displaying API usage metrics — dark theme, data-dense, professional"` — frontend-design skill activates.
2. Skill asks clarifying questions: framework, existing design tokens, target breakpoints.
3. Claude implements the component. `validate-content.sh` checks for placeholder data left in the UI.
4. `"Make the chart section more compact and add a time-range selector"` — iterate with targeted refinements.
5. Final pass: contrast check, responsive review at mobile breakpoint, accessibility attributes verified.

**What happens behind the scenes:**

- `check-mock-in-prod.sh` flags any hardcoded mock data left in the component before it ships.
- `pre-edit-gate.sh` ensures Claude reads the existing component before every incremental edit.
- `validate-content.sh` catches `TODO` and `lorem ipsum` placeholder text in JSX.

---
**Difficulty: Intermediate**


## 12. Audit and improve CLAUDE.md

**Goal:** Systematically improve the project instructions that Claude reads every session.

**Commands used:**
- `/claudetools:claude-md-improver` — audit against quality templates
- `/claudetools:memory` — add cross-session preferences that don't belong in CLAUDE.md

**Workflow:**

1. `"/claudetools:claude-md-improver"` — scans all CLAUDE.md files in the repo, evaluates against quality criteria.
2. Review the quality report: missing sections, outdated commands, contradictory rules.
3. Claude applies targeted improvements — adds missing build/test commands, removes obsolete entries.
4. `"/memory add 'Always run pnpm test before committing'"` — add preferences that should persist but live in memory, not project instructions.
5. Run `"/memory show"` to verify the injected memory block looks correct.

**What happens behind the scenes:**

- `enforce-memory-preferences.sh` checks all ALWAYS/NEVER rules in memory before every edit — including the edits to CLAUDE.md itself.
- `memory-reflect.sh` (Stop hook) extracts new learnings from the session and proposes additions to memory.
- `doc-stale-detector.sh` will warn in future sessions if the updated CLAUDE.md goes 90 days without a review.

---
**Difficulty: Intermediate**


## Related

- [Which Tool Should I Use?](which-tool.md) — decision tree for choosing the right starting point
- [Guides](debug-a-bug.md) — deep walkthroughs of individual workflows
- [Cheat Sheet](../reference/cheat-sheet.md) — all commands, hooks, and agents at a glance
