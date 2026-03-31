# Claudetools v6: Process Skills + Commands Implementation Plan

> **For agentic workers:** Execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is independently committable.

**Goal:** Rewrite 6 process skills to superpowers-depth (170-250 LOC each) with infrastructure integration, consolidate 18 commands down to 8, and update the skill router — making claudetools a standalone engineering workflow plugin.

**Architecture:** Each skill gets 3 layers: iron laws + anti-patterns (process), codebase-pilot + detect-project integration (tooling), validator wiring (enforcement). Three workflow commands (`/design`, `/build`, `/ship`) invoke internal skills. Five specialist commands remain. Ten commands retired (skills still accessible via full name).

**Tech Stack:** Bash (skills, commands, router), YAML frontmatter (SKILL.md), jq (detect-project), codebase-pilot CLI

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `plugin/skills/design/SKILL.md` | Create | Workflow command skill: discover + research + architect + plan |
| `plugin/skills/build/SKILL.md` | Create | Workflow command skill: develop with TDD + test + verify |
| `plugin/skills/ship/SKILL.md` | Create | Workflow command skill: review + PR + CI + deploy |
| `plugin/skills/brainstorm/SKILL.md` | Delete | Replaced by /design |
| `plugin/skills/plan/SKILL.md` | Delete | Folded into /design |
| `plugin/skills/tdd/SKILL.md` | Delete | Folded into /build |
| `plugin/skills/verify/SKILL.md` | Delete | Folded into /build and /ship |
| `plugin/skills/finish/SKILL.md` | Delete | Folded into /ship |
| `plugin/skills/workflow/SKILL.md` | Delete | Replaced by auto-injection via skill-router |
| `plugin/commands/design.md` | Rewrite | Points to design skill |
| `plugin/commands/build.md` | Rewrite | Points to build skill |
| `plugin/commands/ship.md` | Rewrite | Points to ship skill |
| `plugin/commands/workflow.md` | Delete | No longer needed |
| `plugin/commands/claude-code-guide.md` | Delete | Skill accessible via `claudetools:claude-code-guide` |
| `plugin/commands/code-review.md` | Delete | Merged into /review |
| `plugin/commands/docs-manager.md` | Delete | Folded into /ship |
| `plugin/commands/field-review.md` | Delete | Folded into /health |
| `plugin/commands/hook-inventory.md` | Delete | Folded into /health |
| `plugin/commands/logs.md` | Delete | Skill accessible via `claudetools:logs` |
| `plugin/commands/memory.md` | Delete | Skill accessible via `claudetools:memory` |
| `plugin/commands/mesh.md` | Delete | Skill accessible via `claudetools:mesh` |
| `plugin/commands/session-dashboard.md` | Delete | Folded into /health |
| `plugin/scripts/lib/skill-router.sh` | Rewrite | Route to 3 workflow + 5 specialist commands |
| `plugin/scripts/inject-prompt-context.sh` | Modify | Inject compact workflow context, not just hints |

---

### Task 1: Create /design skill (discover + research + architect + plan)

**Files:**
- Create: `plugin/skills/design/SKILL.md`

- [ ] **Step 1: Create the design skill**

Write `plugin/skills/design/SKILL.md` with this exact content:

```markdown
---
name: design
description: >
  Full design phase — discover the problem, research dependencies, architect a
  solution, and write the implementation plan. Use before building anything
  non-trivial. This is the first command in the /design → /build → /ship workflow.
argument-hint: "[what to build or change]"
allowed-tools: Read, Glob, Grep, Bash, WebSearch, WebFetch, Write, AskUserQuestion, Agent
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [design, discovery, architecture, planning, workflow]
---

# /design — Discover, Architect, Plan

> HARD GATE: Do NOT write implementation code until the user has approved the design
> AND the plan is written. This applies to EVERY task regardless of perceived simplicity.

## Why This Gate Exists

| Rationalization | Reality |
|----------------|---------|
| "This is too simple to need a design" | Simple tasks with unexamined assumptions cause the most wasted work |
| "I already know how to do this" | You know how to do it in your training data. This codebase may differ. |
| "Let me just start coding and refactor later" | Refactoring code you shouldn't have written costs 3x more than designing first |
| "The user seems impatient" | A 2-minute design conversation saves 20 minutes of wrong-direction work |

## The Process

### Phase 1: Discover

Understand the problem before solving it.

1. **Explore the codebase** using codebase-pilot:
   ```bash
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<relevant-name>"
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<entry-point>"
   ```

2. **Check memory** for past decisions about this area:
   - Read `$HOME/.claude/projects/*/memory/MEMORY.md` for relevant entries
   - "Last time you worked on auth, you chose JWT because..."

3. **Research external dependencies** (if task touches external APIs/libraries):
   - Use WebSearch + WebFetch to find current documentation
   - Verify API endpoints, SDK versions, auth methods
   - Skip if task is purely internal

4. **Ask clarifying questions** — one at a time via AskUserQuestion:
   - What problem does this solve? (if not obvious)
   - What constraints exist? (performance, compatibility, etc.)
   - What does success look like?

### Phase 2: Architect

Present 2-3 approaches with tradeoffs.

Use AskUserQuestion with preview panels to show each approach:

```
AskUserQuestion:
  question: "Which approach for [feature]?"
  options:
    - label: "Approach A: [name]"
      description: "[1-sentence tradeoff]"
      preview: |
        Architecture:
        [component diagram or code structure]

        Pros: [key advantage]
        Cons: [key disadvantage]
        Files: [N files changed]
    - label: "Approach B: [name]"
      ...
```

Lead with your recommendation. Explain why in 1 sentence.

### Phase 3: Plan

After the user approves an approach, write the implementation plan:

1. **Map files** — use `related-files` and `file-overview` to list every file to create/modify
2. **Write tasks** — each task is one self-contained change:
   - Exact file paths
   - Complete code in every step
   - Test-first: failing test → implementation → verify → commit
   - No placeholders (never write "TBD", "add appropriate handling", "similar to Task N")
3. **Self-review** — check for: spec coverage, placeholder scan, type consistency
4. **Save** to `docs/plans/YYYY-MM-DD-<name>.md`

### Phase 4: Handoff

Present the plan summary and ask:

```
AskUserQuestion:
  question: "Plan ready — N tasks, M files. Start building?"
  options:
    - label: "Build it"
      description: "Execute the plan task-by-task with TDD"
    - label: "Review plan first"
      description: "Show the full plan for review before building"
    - label: "Adjust"
      description: "I want to change something in the design"
```

If "Build it" → tell the user: "Starting build phase. **Next: /build**"

## Safety Net

If /design is followed correctly, these validators should never fire:
- `task-scope.sh` — scope is defined by the plan's acceptance criteria
- `unasked-deps.sh` — dependencies are identified in the discovery phase
- `unasked-restructure.sh` — structural changes are in the plan
- `research-backing.sh` — external APIs were researched in discovery
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/design/SKILL.md
git commit -m "feat: create /design skill (discover + architect + plan)

Full design phase with HARD GATE, rationalization table, codebase-pilot
integration, memory check, AskUserQuestion with preview panels, and
validator safety net mapping."
```

---

### Task 2: Create /build skill (develop + test + verify)

**Files:**
- Create: `plugin/skills/build/SKILL.md`

- [ ] **Step 1: Create the build skill**

Write `plugin/skills/build/SKILL.md` with this exact content:

```markdown
---
name: build
description: >
  Execute an implementation plan with test-driven development. Dispatches fresh
  subagents per task, runs TDD (test first, implement, verify), and tracks progress.
  Second command in the /design → /build → /ship workflow.
argument-hint: "[plan-file-path or 'continue']"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TaskCreate, TaskUpdate
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [build, development, TDD, implementation, workflow]
---

# /build — Develop, Test, Verify

> IRON LAW: No production code without a failing test first. Every task follows
> RED → GREEN → REFACTOR → COMMIT.

## Prerequisites

A plan must exist. If no plan file is provided and none found in `docs/plans/`:
```
"No plan found. Run /design first to create one."
```

## Why Test-First

| Excuse | Reality |
|--------|---------|
| "I'll write tests after" | Tests-after answer "what does this code do?" Tests-first answer "what SHOULD this code do?" — fundamentally different |
| "TDD slows me down" | TDD is faster than debugging. Time spent writing a test: 2 min. Time spent debugging without one: 20 min. |
| "This is too simple to test" | Simple code with tests stays simple. Simple code without tests becomes complex when the next person changes it. |
| "I'll just run it and see" | Manual verification is not repeatable. Automated tests are. |

## The Process

### Step 1: Load the plan

Read the plan file. Extract all tasks with full text.

### Step 2: Detect project test framework

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/lib/detect-project.sh
PROJECT_TYPE=$(detect_project_type)
```

| Project Type | Test Command | Test File Pattern |
|-------------|-------------|-------------------|
| node | `npm test` or `npx vitest` or `npx jest` | `*.test.ts`, `*.spec.ts` |
| python | `pytest` or `python -m unittest` | `test_*.py`, `*_test.py` |
| rust | `cargo test` | `#[cfg(test)]` modules |
| go | `go test ./...` | `*_test.go` |
| shell | `bats tests/` | `*.bats` |

### Step 3: Execute tasks

For each task in the plan:

1. **Show progress:**
   ```
   "Task 3/7: [task name]"
   ```

2. **RED — Write the failing test:**
   - Create the test file with the test code from the plan
   - Run the test command
   - Confirm it FAILS (if it passes, the test is wrong)

3. **GREEN — Write minimal implementation:**
   - Write the minimum code to make the test pass
   - Run the test command
   - Confirm it PASSES

4. **REFACTOR — Clean up:**
   - Remove duplication, improve names, simplify
   - Run tests again — must still pass

5. **COMMIT:**
   ```bash
   git add <specific files>
   git commit -m "feat: [task description]"
   ```

6. **Report:**
   ```
   "✓ Task 3/7 complete. Tests: 12/12 passing."
   ```

### Step 4: Subagent dispatch (for independent tasks)

When the plan has independent tasks (no shared state, different files), dispatch fresh subagents:

```
Agent:
  prompt: "[full task text from plan + project context + TDD instructions]"
  mode: bypassPermissions
  run_in_background: true
```

Each subagent gets:
- The complete task text (not a reference to the plan file)
- Project type and test command
- TDD instructions: "Write failing test first. Run it. Then implement."
- The commit message format

After each subagent completes, verify its work:
- Run the test suite
- Check the commit message
- If issues found, dispatch a fix agent

### Step 5: Final verification

After all tasks complete:

```bash
# Run full test suite
[test command for project type]

# Check for stubs
grep -rn 'TODO\|FIXME\|NotImplementedError\|throw.*not implemented' [source files]

# Verify all plan tasks are committed
git log --oneline -[N]
```

Report:
```
"✓ All 7/7 tasks complete. Tests: 34/34 passing. No stubs. Ready for review."
AskUserQuestion: "Ready to ship?" → /ship
```

## Safety Net

If /build is followed correctly, these validators should never fire:
- `stubs.sh` — TDD eliminates stubs in the RED phase
- `ran-checks.sh` — tests run in every GREEN phase
- `blind-edit.sh` — plan maps all files; nothing is edited without context
- `no-deferred-actions.sh` — every task is completed, not deferred
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/build/SKILL.md
git commit -m "feat: create /build skill (TDD + subagent dispatch + verify)

Full implementation phase with iron law, anti-pattern table, project-aware
test detection, subagent dispatch for independent tasks, and validator
safety net mapping."
```

---

### Task 3: Create /ship skill (review + PR + CI + deploy)

**Files:**
- Create: `plugin/skills/ship/SKILL.md`

- [ ] **Step 1: Create the ship skill**

Write `plugin/skills/ship/SKILL.md` with this exact content:

```markdown
---
name: ship
description: >
  Ship the work — run code review, create PR, verify CI, merge or deploy.
  Third command in the /design → /build → /ship workflow. Ensures nothing ships
  without evidence it works.
argument-hint: "[merge|pr|deploy]"
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion, Agent
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [ship, deploy, review, PR, CI, delivery, workflow]
---

# /ship — Review, Deliver, Deploy

> IRON LAW: Nothing ships without evidence. Tests must pass. Review must complete.
> CI must be green. "It should work" is not evidence.

## The Process

### Phase 1: Pre-flight

Before anything else, verify the work is ready:

```bash
# 1. Tests pass
[project test command]

# 2. No uncommitted changes
git status

# 3. No stubs or TODOs in changed files
git diff --name-only HEAD~[N] HEAD | xargs grep -l 'TODO\|FIXME\|NotImplementedError' || echo "Clean"

# 4. Branch is up to date
git pull --rebase origin main
```

If any check fails, fix it before proceeding. Do not skip.

### Phase 2: Code Review

Run the structured 4-pass review:

1. **Correctness** — Does the code do what it claims? Edge cases handled?
2. **Security** — Hardcoded secrets? Injection risks? Auth issues?
3. **Performance** — N+1 queries? Unnecessary allocations? Missing indexes?
4. **Maintainability** — Clear naming? Reasonable structure? Test coverage?

Report findings. If critical issues found, fix them before proceeding.

### Phase 3: Deliver

Present options via AskUserQuestion:

```
AskUserQuestion:
  question: "How do you want to deliver?"
  options:
    - label: "Create PR"
      description: "Push branch, create PR with structured description, wait for CI"
    - label: "Merge to main"
      description: "Merge directly (small team, already reviewed)"
    - label: "Deploy"
      description: "Create PR, merge when CI passes, deploy to production"
```

**If Create PR:**
```bash
git push -u origin [branch]
gh pr create --title "[title]" --body "$(cat <<'EOF'
## Summary
[2-3 bullet points from the plan]

## Test Plan
[What was tested and how]

## Changes
[File count and nature of changes]
EOF
)"
```

Then monitor CI:
```bash
gh pr checks [PR-number] --watch
```

Report: "PR #[N] created. CI: ✓ all checks passing. Ready to merge."

**If Merge:**
```bash
git checkout main
git merge --no-ff [branch] -m "feat: [description]"
git push origin main
```

**If Deploy:**
After PR merge, detect deployment platform:
- `wrangler.jsonc` → Cloudflare Workers: `npx wrangler deploy`
- `vercel.json` → Vercel: `npx vercel --prod`
- `Dockerfile` → Docker: `docker build && docker push`
- `fly.toml` → Fly.io: `fly deploy`

Post-deploy: check health endpoint if available, report status.

### Phase 4: Documentation

If docs were changed:
```bash
# Reindex documentation
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-reindex.sh
```

### Phase 5: Record

Save session context to memory for future sessions:
- What was built and why
- Key decisions made
- Deployment status

## Safety Net

If /ship is followed correctly, these validators should never fire:
- `session-stop-gate` Tier 1 — no uncommitted changes (pre-flight catches them)
- `session-stop-gate` Tier 2 — no weasel phrases (evidence-based reporting)
- `git-commits.sh` — committed properly with conventional messages
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/ship/SKILL.md
git commit -m "feat: create /ship skill (review + PR + CI + deploy)

Full delivery phase with pre-flight checks, 4-pass code review,
PR creation via gh CLI, CI monitoring, deployment detection, and
post-deploy verification."
```

---

### Task 4: Delete old process skills and workflow

**Files:**
- Delete: `plugin/skills/brainstorm/SKILL.md`
- Delete: `plugin/skills/plan/SKILL.md`
- Delete: `plugin/skills/tdd/SKILL.md`
- Delete: `plugin/skills/verify/SKILL.md`
- Delete: `plugin/skills/finish/SKILL.md`
- Delete: `plugin/skills/workflow/SKILL.md`

- [ ] **Step 1: Delete the old skills**

```bash
rm -r plugin/skills/brainstorm plugin/skills/plan plugin/skills/tdd plugin/skills/verify plugin/skills/finish plugin/skills/workflow
```

- [ ] **Step 2: Commit**

```bash
git add -A plugin/skills/brainstorm plugin/skills/plan plugin/skills/tdd plugin/skills/verify plugin/skills/finish plugin/skills/workflow
git commit -m "chore: remove old process skills replaced by /design /build /ship

brainstorm, plan, tdd, verify, finish, workflow replaced by three
workflow skills: design (discover+architect+plan), build (TDD+verify),
ship (review+deploy)."
```

---

### Task 5: Rewrite /design /build /ship commands

**Files:**
- Rewrite: `plugin/commands/design.md`
- Rewrite: `plugin/commands/build.md`
- Rewrite: `plugin/commands/ship.md`

- [ ] **Step 1: Rewrite design.md**

```markdown
---
description: "Design phase — discover the problem, research dependencies, architect a solution, write the plan. First step: /design → /build → /ship"
argument-hint: "[what to build or change]"
---

Invoke the `claudetools:design` skill with the user's arguments.
```

- [ ] **Step 2: Rewrite build.md**

```markdown
---
description: "Build phase — execute the plan with test-driven development, dispatch subagents for independent tasks. Second step: /design → /build → /ship"
argument-hint: "[plan-file-path or 'continue']"
---

Invoke the `claudetools:build` skill with the user's arguments.
```

- [ ] **Step 3: Rewrite ship.md**

```markdown
---
description: "Ship phase — code review, create PR, verify CI, merge or deploy. Final step: /design → /build → /ship"
argument-hint: "[merge|pr|deploy]"
---

Invoke the `claudetools:ship` skill with the user's arguments.
```

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/design.md plugin/commands/build.md plugin/commands/ship.md
git commit -m "feat: rewrite workflow commands for /design /build /ship"
```

---

### Task 6: Retire 10 commands

**Files:**
- Delete: `plugin/commands/workflow.md`
- Delete: `plugin/commands/claude-code-guide.md`
- Delete: `plugin/commands/code-review.md`
- Delete: `plugin/commands/docs-manager.md`
- Delete: `plugin/commands/field-review.md`
- Delete: `plugin/commands/hook-inventory.md`
- Delete: `plugin/commands/logs.md`
- Delete: `plugin/commands/memory.md`
- Delete: `plugin/commands/mesh.md`
- Delete: `plugin/commands/session-dashboard.md`

- [ ] **Step 1: Delete retired commands**

```bash
rm plugin/commands/workflow.md plugin/commands/claude-code-guide.md plugin/commands/code-review.md plugin/commands/docs-manager.md plugin/commands/field-review.md plugin/commands/hook-inventory.md plugin/commands/logs.md plugin/commands/memory.md plugin/commands/mesh.md plugin/commands/session-dashboard.md
```

- [ ] **Step 2: Verify remaining commands**

```bash
ls plugin/commands/
```

Expected: `build.md  debug.md  design.md  explore.md  health.md  research.md  review.md  ship.md` (8 files)

- [ ] **Step 3: Commit**

```bash
git add -A plugin/commands/
git commit -m "chore: retire 10 commands — skills still accessible via full name

Removed: workflow, claude-code-guide, code-review, docs-manager,
field-review, hook-inventory, logs, memory, mesh, session-dashboard.
These skills are still invocable as claudetools:skill-name.
Remaining 8 commands: design, build, ship, debug, explore, research, review, health."
```

---

### Task 7: Rewrite skill-router for 3+5 commands

**Files:**
- Rewrite: `plugin/scripts/lib/skill-router.sh`

- [ ] **Step 1: Rewrite the router**

Replace `plugin/scripts/lib/skill-router.sh` entirely:

```bash
#!/usr/bin/env bash
# skill-router.sh — Tier 1 intent classification for workflow injection
# Maps user prompts to workflow commands. Returns command name or empty.

classify_intent() {
  local text="${1:-}"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  # Debug/fix → /debug (check first — most specific)
  case "$lower" in
    *debug*|*"fix this"*|*"fix the"*|*"why is"*failing*|*"not working"*|*broken*|*"unexpected behav"*|*error*traceback*|*stacktrace*)
      echo "debug"; return 0 ;;
  esac

  # Explore/navigate → /explore
  case "$lower" in
    *"where is"*|*"find where"*|*"trace the"*|*"how does"*work*|*"explore"*code*|*"show me"*|*"what calls"*)
      echo "explore"; return 0 ;;
  esac

  # Research → /research
  case "$lower" in
    *"research"*|*"look up"*doc*|*"check the"*api*|*"find doc"*|*"what api"*|*"how does"*api*)
      echo "research"; return 0 ;;
  esac

  # Review → /review
  case "$lower" in
    *"review"*code*|*"code review"*|*"audit"*code*|*"check quality"*)
      echo "review"; return 0 ;;
  esac

  # Health/metrics → /health
  case "$lower" in
    *"health"*|*"metrics"*|*"session stat"*|*"hook perform"*|*"how is the plugin"*)
      echo "health"; return 0 ;;
  esac

  # Ship/deploy/merge → /ship
  case "$lower" in
    *"merge"*|*"create pr"*|*"pull request"*|*deploy*|*publish*|*release*|*"ship it"*|*"push to"*)
      echo "ship"; return 0 ;;
  esac

  # Build/create/implement → /design (design first, not straight to build)
  case "$lower" in
    *build*|*create*|*implement*|*"add feature"*|*"add a "*|*"new feature"*|*"write a "*|*refactor*|*restructure*|*"set up"*|*"integrate"*)
      echo "design"; return 0 ;;
  esac

  echo ""
  return 0
}

# format_workflow_context COMMAND → echoes compact workflow injection
format_workflow_context() {
  local cmd="${1:-}"
  case "$cmd" in
    design)
      cat <<'CTX'
[workflow] This task needs the design phase first. Follow this process:
1. DISCOVER: Explore codebase (codebase-pilot), check memory, research external deps
2. ARCHITECT: Present 2-3 approaches via AskUserQuestion with preview panels
3. PLAN: Write implementation plan with exact file paths and TDD steps
4. HANDOFF: Ask user "Ready to build?" → /build
Do NOT write implementation code until the plan is approved.
CTX
      ;;
    build)
      cat <<'CTX'
[workflow] Build phase. Execute the plan with test-driven development:
- For each task: write failing test → implement → verify → commit
- Dispatch subagents for independent tasks
- Report progress: "Task N/M complete. Tests: X/Y passing."
- After all tasks: "Ready to ship?" → /ship
CTX
      ;;
    ship)
      cat <<'CTX'
[workflow] Ship phase. Deliver with evidence:
1. Pre-flight: tests pass, no uncommitted changes, branch up to date
2. Code review: correctness, security, performance, maintainability
3. Deliver: create PR (gh pr create), monitor CI (gh pr checks --watch)
4. Report: "PR #N created. CI: ✓ passing."
CTX
      ;;
    debug)
      echo "[workflow] Debug: reproduce → observe → hypothesize → verify → fix → confirm. Evidence before fixes." ;;
    explore)
      echo "[workflow] Explore: use codebase-pilot (map, find-symbol, related-files) to understand the code." ;;
    research)
      echo "[workflow] Research: find current docs (WebSearch), verify API endpoints, check SDK versions before implementing." ;;
    review)
      echo "[workflow] Review: 4-pass (correctness → security → performance → maintainability)." ;;
    health)
      echo "[workflow] Health: run session-dashboard + field-review for combined metrics." ;;
  esac
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n plugin/scripts/lib/skill-router.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/lib/skill-router.sh
git commit -m "feat: rewrite skill-router for 3+5 command workflow

Routes to: design, build, ship (workflow) + debug, explore, research,
review, health (specialist). Implementation intents go to /design first.
format_workflow_context injects compact process instructions per command."
```

---

### Task 8: Update inject-prompt-context.sh to use workflow context

**Files:**
- Modify: `plugin/scripts/inject-prompt-context.sh`

- [ ] **Step 1: Read the current file**

Run: `cat -n plugin/scripts/inject-prompt-context.sh`

Find the skill-router section (added in Phase 2, around lines 35-48). Currently it calls `format_skill_hint` which outputs a one-line hint.

- [ ] **Step 2: Replace skill hint with workflow context injection**

Change the skill-router block from:

```bash
MATCHED_SKILL=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_SKILL" ]; then
  SKILL_HINT=$(format_skill_hint "$MATCHED_SKILL")
  echo "$SKILL_HINT"
  ...telemetry...
fi
```

To:

```bash
MATCHED_CMD=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_CMD" ]; then
  WORKFLOW_CTX=$(format_workflow_context "$MATCHED_CMD")
  echo "$WORKFLOW_CTX"
  source "$(dirname "$0")/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_CMD" "$SESSION_ID" "keyword" 2>/dev/null || true
fi
```

The key change: `format_skill_hint` (one-line hint) → `format_workflow_context` (3-5 line process summary). The agent gets the workflow instructions automatically.

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/inject-prompt-context.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/inject-prompt-context.sh
git commit -m "feat: inject workflow context instead of skill hints

UserPromptSubmit now injects compact 3-5 line workflow instructions
for the detected intent. Agent gets process guidance automatically
without invoking skills manually."
```

---

## Self-Review

1. **Spec coverage:**
   - ✓ Part A (process skills): Tasks 1-3 create /design, /build, /ship with full depth
   - ✓ Command consolidation: Tasks 5-6 reduce 18 → 8 commands
   - ✓ Skill-router update: Task 7 rewrites for 3+5 commands
   - ✓ Auto-injection: Task 8 upgrades from hints to workflow context
   - ✓ Old skills removed: Task 4 deletes 6 replaced skills
   - Part B (hook consolidation): Separate plan
   - Part C (CI/CD): Covered in /ship skill's deploy phase
   - Part D (subagent dispatch): Covered in /build skill's Step 4

2. **Placeholder scan:** No TBD, TODO, "implement later", or "similar to Task N" found. All code complete.

3. **Type consistency:** `classify_intent` returns command names (`design`, `build`, `ship`, `debug`, etc.) consistently. `format_workflow_context` takes the same command names. Validator safety net references match actual validator filenames.
