# Workflow Gap Analysis: Senior Engineer Workflow Coverage

> Map the complete senior software engineering workflow, identify which skills cover each phase, and find gaps.

---

## The Workflow

A senior engineer doesn't just write code. They follow a disciplined cycle:

```
UNDERSTAND → DESIGN → IMPLEMENT → VERIFY → REVIEW → SHIP → MAINTAIN
```

Each phase has specific activities. Each activity should map to a skill. Gaps mean the agent falls back to ad-hoc behavior — which is where quality drops.

---

## Phase-by-Phase Coverage

### 1. UNDERSTAND — Learn before you act

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Explore unfamiliar codebase | codebase-explorer | — | No |
| Research external APIs/libraries | **NONE** | — | **YES** |
| Read and understand a ticket/issue | — | — | **YES** |
| Understand plugin/extension patterns | claude-code-guide | — | No |
| Recall past decisions/context | memory | episodic-memory:search | No |

**Gaps found:**
- **No research skill.** The `research-backing` validator catches missing research AFTER code is written. There's no proactive skill that says "before implementing code that touches external APIs, research the current docs first." The `find-docs` superpowers skill exists but is a reference lookup, not a structured research workflow.
- **No ticket/issue comprehension skill.** When given a GitHub issue or Jira ticket, there's no skill that structures the understanding phase: read the issue, identify acceptance criteria, check related issues, understand the user's actual problem vs their stated request.

### 2. DESIGN — Think before you build

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Brainstorm approaches | **NONE** | brainstorming | Covered by superpowers |
| Write implementation plan | **NONE** | writing-plans | Covered by superpowers |
| Design prompts/instructions | prompt-improver | — | No |
| Design UI/frontend | frontend-design | — | No |
| Architectural review | **NONE** | — | **YES** |

**Gaps found:**
- **No architectural review skill.** For changes that affect system architecture (new subsystems, database schema changes, API contracts), there's no skill that enforces architectural thinking: "What are the tradeoffs? What does this couple to? What becomes harder to change later?" The code-review skill covers post-implementation review, not pre-implementation design review.

### 3. IMPLEMENT — Build with discipline

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Set up isolated workspace | **NONE** | using-git-worktrees | Covered by superpowers |
| TDD (test-first) | **NONE** | test-driven-development | Covered by superpowers |
| Execute plan task-by-task | **NONE** | executing-plans, subagent-driven-dev | Covered by superpowers |
| Dispatch parallel agents | **NONE** | dispatching-parallel-agents | Covered by superpowers |
| Track tasks/progress | task-manager | — | No |
| Self-review while coding | **NONE** | — | **YES** (partially covered by validators) |

**Gaps found:**
- **No structured self-review skill.** Validators catch specific issues (stubs, secrets, scope), but there's no skill that prompts the agent to self-review before committing: "Does this change do what I intended? Did I miss anything? Is there a simpler way?" Superpowers' implementer prompt includes self-review, but it's embedded in the subagent workflow, not a standalone skill.

### 4. VERIFY — Prove it works

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Run tests and check output | **NONE** | verification-before-completion | Covered by superpowers |
| Debug failures | debugger | systematic-debugging | No (both exist) |
| Run safety/training scenarios | safety-evaluator | — | No |
| Check deployment health | session-dashboard, field-review | — | No |

**No gaps.** Verification is well-covered between claudetools and superpowers.

### 5. REVIEW — Get and give feedback

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Request code review | code-review | requesting-code-review | No (both exist) |
| Respond to review feedback | **NONE** | receiving-code-review | Covered by superpowers |
| Review others' code | code-review | — | No |

**No gaps.** Review is well-covered.

### 6. SHIP — Deliver with confidence

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Finish branch (merge/PR) | **NONE** | finishing-a-development-branch | Covered by superpowers |
| Update documentation | docs-manager | — | No |
| Deploy | **NONE** | cloudflare-deploy | Covered by superpowers |
| Monitor after deploy | session-dashboard | — | Partial |

**Gaps found:**
- **No post-deploy monitoring skill.** `session-dashboard` shows plugin health, but there's no skill for monitoring a deployed application: check error rates, verify endpoints, watch logs after deployment. This is a real gap for production software.

### 7. MAINTAIN — Keep it healthy

| Activity | Claudetools Skill | Superpowers Skill | Gap? |
|----------|------------------|-------------------|------|
| Debug production issues | debugger | systematic-debugging | No |
| Analyze session logs | logs | — | No |
| Cross-session memory | memory | episodic-memory | No |
| Plugin self-improvement | plugin-improver | — | No |
| Health monitoring | field-review, session-dashboard | — | No |

**No gaps.** Maintenance is well-covered.

---

## Gap Summary

| Gap | Phase | Impact | Recommendation |
|-----|-------|--------|----------------|
| **Research skill** | Understand | HIGH — agents write code against stale API assumptions | Create a research skill that enforces: read current docs, check version compatibility, verify endpoints exist BEFORE writing code |
| **Issue comprehension** | Understand | MEDIUM — agents jump to implementation without understanding the real problem | Create a skill or add to codebase-explorer: parse issue, extract acceptance criteria, identify related code |
| **Architectural review** | Design | MEDIUM — no pre-implementation design review for structural changes | Create a skill that enforces tradeoff analysis for changes touching >5 files or adding new subsystems |
| **Self-review** | Implement | LOW — validators partially cover this, but reactively | Consider a lightweight pre-commit skill (or strengthen the session-stop-gate Tier 2 checks) |
| **Post-deploy monitoring** | Ship | LOW — niche, most claudetools users are in dev not ops | Defer unless user requests |

---

## The Orchestration Gap

The biggest gap isn't a missing skill — it's a missing **conductor**.

Currently, the agent must decide which skill to use at each phase. The `skill-router.sh` intent classifier maps keywords to individual skills, but it doesn't enforce the workflow order. An agent can jump straight to implementation without brainstorming. It can ship without verification.

**Superpowers solves this with `using-superpowers`** — a meta-skill that forces skill invocation before any action. But superpowers' workflow is linear: brainstorm → plan → implement → verify → ship.

**What's missing:** A claudetools workflow skill that:
1. Maps the current task to a workflow phase
2. Enforces phase ordering (can't implement without design, can't ship without verification)
3. Routes to the right skill at each phase (claudetools or superpowers)
4. Tracks which phases are complete

This is the equivalent of superpowers' `using-superpowers`, but adapted for the claudetools ecosystem where both plugin systems coexist.

---

## Skill-Router Update

The current `skill-router.sh` only maps to claudetools skills. It should also route to superpowers skills where they're the better fit:

| Intent Pattern | Current Routing | Should Route To |
|---------------|----------------|-----------------|
| build, create, implement, add feature | (none) | superpowers:brainstorming → superpowers:writing-plans |
| fix, debug, broken, error | debugger | debugger (correct) |
| review, audit, check quality | code-review | code-review (correct) |
| explore, find, where is, trace | codebase-explorer | codebase-explorer (correct) |
| deploy, publish, release | (none) | superpowers:finishing-a-development-branch |
| test, verify, check if works | (none) | superpowers:verification-before-completion |
| research, docs, API, library | (none) | **NEW: research skill** |
| plan, design, architect | (none) | superpowers:writing-plans |
| refactor, restructure, reorganize | (none) | superpowers:brainstorming (design first) |

---

## Recommended New Skills

### 1. research (HIGH priority)

**Purpose:** Before implementing code that touches external APIs, libraries, or unfamiliar systems, research current documentation and verify assumptions.

**Workflow:**
1. Identify what external systems the task touches
2. Find current documentation (WebSearch, WebFetch, find-docs)
3. Verify API endpoints/methods still exist
4. Check version compatibility
5. Document findings as context for implementation

**Why:** The `research-backing` validator blocks code that lacks research evidence. But it blocks AFTER code is written — wasting the implementation work. A proactive research skill prevents this entirely.

### 2. workflow-conductor (HIGH priority)

**Purpose:** Meta-skill that orchestrates the full engineering workflow, ensuring no phase is skipped.

**Workflow:**
1. Classify the task (bug fix? new feature? refactor? research?)
2. Map to required phases (bug fix: understand → debug → fix → verify → ship)
3. At each phase transition, verify the previous phase is complete
4. Route to the appropriate skill (claudetools or superpowers) at each phase

**Why:** Without a conductor, the agent decides ad-hoc which skills to use and in what order. This is where quality drops — agents skip design, skip verification, skip review. The conductor makes the workflow mandatory.

### 3. architecture-review (MEDIUM priority)

**Purpose:** Pre-implementation design review for structural changes.

**Triggers:** Changes touching >5 files, new subsystems, database schema changes, API contract changes.

**Workflow:**
1. What are we changing and why?
2. What does this couple to?
3. What becomes harder to change later?
4. What are the alternatives?
5. What's the simplest approach that solves the actual problem?

---

## Workflow Diagram: Complete Coverage After Fixes

```
UNDERSTAND
  ├─ codebase-explorer (explore code)
  ├─ research [NEW] (external APIs/docs)
  ├─ memory (recall past context)
  └─ claude-code-guide (plugin patterns)
       ↓
DESIGN
  ├─ superpowers:brainstorming (explore approaches)
  ├─ superpowers:writing-plans (create plan)
  ├─ architecture-review [NEW] (structural changes)
  ├─ prompt-improver (prompt design)
  └─ frontend-design (UI design)
       ↓
IMPLEMENT
  ├─ superpowers:using-git-worktrees (isolation)
  ├─ superpowers:test-driven-development (TDD)
  ├─ superpowers:subagent-driven-development (execution)
  ├─ task-manager (progress tracking)
  └─ workflow-conductor [NEW] (enforce phase order)
       ↓
VERIFY
  ├─ superpowers:verification-before-completion
  ├─ debugger / superpowers:systematic-debugging
  └─ safety-evaluator (safety scenarios)
       ↓
REVIEW
  ├─ code-review / superpowers:requesting-code-review
  └─ superpowers:receiving-code-review
       ↓
SHIP
  ├─ superpowers:finishing-a-development-branch
  └─ docs-manager (documentation)
       ↓
MAINTAIN
  ├─ debugger (production issues)
  ├─ logs (session analysis)
  ├─ memory (cross-session knowledge)
  ├─ field-review (plugin health)
  ├─ session-dashboard (metrics)
  └─ plugin-improver (self-improvement)
```

**With these 3 additions, every phase of the senior engineer workflow has explicit skill coverage.**
