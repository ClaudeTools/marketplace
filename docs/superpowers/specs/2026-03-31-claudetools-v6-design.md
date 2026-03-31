# Claudetools v6: Standalone Excellence

> Three commands. Full engineering workflow. Agent leads, user steers.
>
> `/design` → `/build` → `/ship`

---

## Problem

Users shouldn't need to memorize 15 slash commands. They should learn three — `/design`, `/build`, `/ship` — and get senior-engineer-quality work. The agent leads the workflow, walks the user through decisions with rich interactive tools, and handles everything between decision points.

Claudetools has infrastructure but thin process skills. Superpowers has deep skills but zero infrastructure. Claudetools v6 combines both into three elegant workflow commands backed by real enforcement.

## The Workflow

```
/design → /build → /ship
```

| Command | Covers Internally | User Decision |
|---------|------------------|--------------|
| `/design` | Discover + research + architect + plan | "What are we building and how?" |
| `/build` | Develop with TDD + test + verify | "Go build it" |
| `/ship` | Review + PR + CI + deploy + monitor | "Ship it" |

**Specialist commands** (standalone use):
`/debug` `/explore` `/research` `/review` `/health`

**Internal skills** (invoked by workflow commands, not user-facing):
discover, architect, plan, tdd, verify, finish, cicd

## Five Design Pillars

### 1. Agent-Led, User-Guided Workflow (NEW — surpasses both)

The agent drives the engineering workflow. The user makes decisions. The interaction is rich, visual, and low-friction — not "zero-touch" silence.

**The model:** A senior engineer pair-programming with you. They lead the conversation, present options visually, explain tradeoffs, and ask for your decision. You steer, they execute.

**How it works:**
- `UserPromptSubmit` hook classifies intent, injects the workflow context automatically
- The agent walks the user through each phase using rich interaction tools:
  - **AskUserQuestion** with preview panels for comparing approaches (code snippets, architecture diagrams, mockup ASCII art)
  - **Visual companion** (localhost server) for UI mockups, diagrams, side-by-side comparisons — adapted from superpowers' brainstorming visual companion
  - **Structured progress updates** at phase transitions ("Design approved. Moving to planning.")
- The user makes lightweight decisions (pick from options, approve/reject, refine)
- The agent handles all execution between decisions

**What the user sees:**
```
User: "build me a login system with OAuth"

Agent: "I've explored the codebase. Here are 3 approaches:"
       [AskUserQuestion with preview panels showing each approach's architecture]

User: picks Option B

Agent: "Good choice. Here's the implementation plan — 6 tasks."
       [Shows plan summary, asks "Ready to start building?"]

User: "go"

Agent: [implements task by task with TDD, shows progress]
       "All 6 tasks complete. Tests passing. Here's the diff summary."
       [AskUserQuestion: "Create PR and check CI?" / "Merge directly?" / "Review first?"]

User: picks "Create PR"

Agent: "PR #42 created. CI running... ✓ All checks pass. Ready to merge?"
```

**The key insight:** The agent leads, the user steers. Slash commands remain available as shortcuts, but the agent proactively drives the workflow without being asked. Every decision point is interactive, not silent.

### 2. Deep Process Skills (matches superpowers)
- Iron laws and HARD GATES
- Rationalization prevention tables
- Worked examples with `<reasoning>` tags
- Decision boundary examples

### 2. Infrastructure Integration (surpasses superpowers)
- Codebase-pilot for project-aware context
- detect-project.sh for language/framework detection
- Metrics DB for historical patterns
- Episodic memory for past decisions
- Subagent dispatch with review gates

### 3. Validator Safety Net (unique to claudetools)
- Each skill maps to specific validators
- If skill process is followed, mapped validators never fire
- Validator fires = process was skipped = go back
- Correlation tracked in health-report.sh

---

## Part A: Process Skill Rewrites

### brainstorm (69 → 200 LOC)

**What it does:** Explore intent, requirements, and design before implementation.

**Additions:**
- HARD GATE with rationalization table ("too simple to need design" → every unexamined assumption causes wasted work)
- Codebase exploration using codebase-pilot: `find-symbol`, `related-files`, `file-overview` to understand existing patterns BEFORE proposing changes
- Memory integration: check episodic memory for past decisions about this area of the codebase
- Decision boundary examples showing when to brainstorm vs when to skip (single-line fix = skip, anything touching >2 files = brainstorm)
- Explicit handoff: "Design approved. **Next: /plan**"

**Safety net validators:** If brainstorming is followed, `task-scope.sh` and `unasked-restructure.sh` should never fire.

### plan (63 → 200 LOC)

**What it does:** Write a concrete implementation plan with bite-sized TDD tasks.

**Additions:**
- File structure mapping using `related-files` and `file-overview` from codebase-pilot
- No-placeholder enforcement: list of 15 forbidden patterns ("TBD", "add appropriate handling", "similar to Task N", etc.)
- Self-review checklist: spec coverage, placeholder scan, type consistency (from superpowers writing-plans)
- Task granularity: each step is ONE action (2-5 min), with worked example
- Save location: `docs/plans/YYYY-MM-DD-<name>.md`
- Handoff: "Plan complete. **Next: /build**"

**Safety net validators:** If plan is followed, `blind-edit.sh` and `unasked-deps.sh` should never fire (deps are in the plan, files are mapped).

### tdd (50 → 200 LOC)

**What it does:** RED-GREEN-REFACTOR cycle enforcement.

**Additions:**
- Iron law: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"
- Rationalization table: "I'll test after" (tests-after prove what code does, tests-first prove what code SHOULD do), "TDD slows me down" (TDD is faster than debugging, measured), "This is too simple to test" (simple code with tests stays simple; simple code without tests becomes complex)
- Project-aware test commands: detect test framework via `detect-project.sh`, suggest exact commands (`npm test`, `pytest`, `cargo test`, `go test`, `bats`)
- Worked example: full RED-GREEN-REFACTOR cycle with actual code
- Memory integration: recall project-specific test patterns from past sessions
- Subagent dispatch: when building from a plan, dispatch a fresh agent per task with TDD instructions

**Safety net validators:** If TDD is followed, `stubs.sh` should never fire (no stubs survive the RED phase), `ran-checks.sh` should never fire (tests were run in every GREEN phase).

### verify (68 → 180 LOC)

**What it does:** Evidence-based completion claims.

**Additions:**
- Iron law: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"
- Auto-detect verification commands via detect-project.sh
- Evidence format: structured, machine-readable (not just prose)
- Forbidden phrases list with technical explanation of why each is a red flag
- Worked examples: GOOD verification report vs BAD ("should work") report
- Integration with session-stop-gate: the weasel phrase detector IS the enforcement layer

**Safety net validators:** If verify is followed, session-stop-gate Tier 2 (weasel phrases) should never fire, `no-deferred-actions.sh` should never fire.

### finish (61 → 170 LOC)

**What it does:** Complete a development branch with confidence.

**Additions:**
- Pre-flight checklist that CALLS verify skill (not just suggests it)
- Git state integration: detect uncommitted changes, unpushed commits, merge conflicts via git-state.sh
- Decision tree: merge vs PR vs cleanup with clear criteria
- Post-delivery checklist: docs update, plugin sync, monitoring
- Memory integration: record what was delivered for cross-session context

**Safety net validators:** If finish is followed, session-stop-gate Tier 1 (uncommitted changes, main branch) should never fire.

### workflow (98 → 250 LOC)

**What it does:** Orchestrate the full engineering cycle.

**Additions:**
- Task classification with worked examples (6 task types → 6 workflows)
- Phase enforcement: check which validators have fired this session to detect skipped phases
- Memory integration: "Last time you worked on this codebase, you used workflow X"
- Subagent coordination: for /build, dispatch fresh agents per plan task with review between each
- Explicit phase transitions with evidence gates
- Integration with skill-router: the workflow IS the intent classifier in action

**Unique advantage:** No other plugin can check validator outcomes to detect skipped phases. If `stubs.sh` fires, the workflow knows TDD was skipped. If `task-scope.sh` fires, brainstorming was skipped. This is measurable process enforcement.

---

## Part B: Hook Consolidation (54 → ~12 entries)

### Current: 54 entries across 17 event types

Each tool matcher gets its own entry. Pre-edit, pre-bash, pre-read all separate. Multiple SessionStart hooks. Multiple Stop hooks.

### Proposed: Universal dispatchers

| Event | Current Entries | Proposed | How |
|-------|----------------|----------|-----|
| PreToolUse | 10 | 1 | Universal dispatcher reads tool name, routes internally |
| PostToolUse | 12 | 1 | Universal dispatcher reads tool name, routes internally |
| SessionStart | 6 | 1 | Single dispatcher calls all startup scripts sequentially |
| Stop | 4 | 1 | Single dispatcher: sync validators + spawn async workers |
| SessionEnd | 3 | 1 | Single async dispatcher |
| UserPromptSubmit | 1 | 1 | Already singular |
| TaskCompleted | 1 | 1 | Already singular |
| SubagentStart | 2 | 1 | Merge into single script |
| SubagentStop | 2 | 1 | Merge into single script |
| PermissionRequest | 1 | 1 | Already singular |
| PostToolUseFailure | 2 | 1 | Merge into single script |
| PreCompact | 1 | 1 | Already singular |
| PostCompact | 1 | 1 | Already singular |
| Remaining (4 event types) | 9 | 0 | Fold into nearest dispatcher or remove |

**Result: 54 entries → 12 entries.** All scripts still execute — just routed by dispatchers instead of by hooks.json matchers.

### Universal PreToolUse Dispatcher

The biggest consolidation. Replace 10 entries with 1:

```bash
#!/bin/bash
# pre-tool-dispatcher.sh — Universal PreToolUse router
# Reads tool name from INPUT, routes to appropriate validators

TOOL_NAME=$(hook_get_field '.tool_name')

case "$TOOL_NAME" in
  Bash)    source validators/dangerous-bash.sh; ... ;;
  Read)    source validators/guard-context-reread.sh; ... ;;
  Edit|Write) source validators/stubs.sh; source validators/secrets.sh; ... ;;
  Agent)   source validators/enforce-team-usage.sh; ... ;;
  Grep)    source scripts/intercept-grep.sh; ... ;;
esac
```

This is the Intelligence Spectrum applied to hook registration: Tier 1 routing (case statement) before Tier 2/3 validation.

---

## Part C: Memory Integration

### Episodic memory in process skills

Each process skill checks memory before starting:

```bash
# In brainstorm skill:
# "Last time you worked on auth in this project, you chose JWT because..."
# "The user prefers small PRs over large refactors"
# "This codebase uses Vitest, not Jest"
```

Implementation: skills reference `${CLAUDE_PLUGIN_ROOT}/scripts/lib/health-report.sh` and the episodic memory MCP tools to query past context.

### Decision recording

After key decisions (approach chosen, pattern selected, tradeoff made), skills prompt the agent to save to memory:

```
"Save this decision to memory for future sessions?
  Decision: chose streaming over polling for real-time updates
  Reason: lower latency, existing WebSocket infrastructure"
```

---

## Part D: Subagent Dispatch in /build

The /build command dispatches fresh agents per plan task:

1. Read the plan file
2. For each task:
   a. Dispatch implementer agent with task text + project context
   b. Implementer follows TDD skill (test first, implement, verify)
   c. After completion, dispatch review agent (claudetools:code-review)
   d. If review has issues, send back to implementer
   e. Mark task complete
3. After all tasks, run full verification

This matches superpowers' subagent-driven-development but is built into the /build command natively.

---

## Part E: CI/CD Integration

### The Gap

Claudetools has zero CI/CD capability. A senior engineer:
1. Writes CI config (GitHub Actions, GitLab CI)
2. Sets up test/lint/typecheck pipelines
3. Creates PRs with structured descriptions
4. Checks CI status before merging
5. Deploys with confidence
6. Monitors after deployment

### New Skill: cicd

**Purpose:** Automate the entire delivery pipeline — from PR creation to CI verification to merge.

**Capabilities:**
- Detect CI platform from project files (`.github/workflows/`, `.gitlab-ci.yml`, etc.)
- Create PRs with structured descriptions (summary, test plan, breaking changes) via `gh` CLI
- Monitor CI status: `gh run watch` or `gh pr checks`
- Block merge until CI passes
- Write/debug CI configurations when they don't exist
- Detect common CI issues (missing secrets, wrong Node version, test timeouts)

**Integration with /ship:**
The `/ship` command's workflow becomes:
1. `/verify` — confirm tests pass locally
2. `/finish` — decide merge vs PR
3. If PR: `cicd` skill creates it with structured body
4. Wait for CI: `cicd` monitors `gh run list` until green
5. If CI fails: diagnose and fix automatically
6. If CI passes: merge (or report ready-to-merge)

**Hooks integration:**
- Post-push hook: check if CI workflows exist, warn if not
- Add `gh` CLI detection to detect-project.sh
- Track CI pass/fail rates in metrics.db for health reporting

### New Skill: deploy

**Purpose:** Deploy applications with pre-flight checks and post-deploy monitoring.

**Capabilities:**
- Detect deployment platform from project config (Cloudflare wrangler.jsonc, Vercel vercel.json, Docker, etc.)
- Run pre-flight: tests pass, no uncommitted changes, correct branch, env vars set
- Execute deployment command
- Post-deploy verification: health check endpoint, error rate monitoring
- Rollback if health check fails

**Integration with workflow:**
Deploy becomes the optional final phase after /ship for projects that have deployment configured.

---

## Part F: Agent-Led Interaction Design

### Workflow Injection

When the UserPromptSubmit hook detects implementation intent, it injects a compact workflow context (10 lines) that tells the agent:
1. Which workflow applies (new-feature, bug-fix, refactor, etc.)
2. What phases to follow in order
3. To use AskUserQuestion at every decision point
4. That slash commands are available as shortcuts if the user wants to jump ahead

### Rich Decision Points

At every phase transition and major decision, the agent uses interactive tools:

**AskUserQuestion with previews** — for comparing approaches:
```
Question: "Which authentication approach?"
Options:
  A: JWT tokens [preview: architecture diagram, pros/cons]
  B: Session cookies [preview: architecture diagram, pros/cons]
  C: OAuth only [preview: architecture diagram, pros/cons]
```

**Visual companion** (localhost server) — for UI design, complex diagrams:
- Spin up local HTTP server to display HTML mockups
- User clicks to select options in the browser
- Agent reads selections from event file
- Same pattern as superpowers' brainstorming visual companion

**Progress updates** — at phase transitions:
```
"✓ Design approved. Writing implementation plan..."
"✓ Plan: 6 tasks. Starting build phase."
"✓ Task 3/6 complete. Tests: 12/12 passing."
"✓ All tasks done. Running code review..."
```

### Intent-to-Workflow Mapping

| Detected Intent | Workflow | Phases |
|----------------|----------|--------|
| New feature / build / create | new-feature | understand → design → plan → build → review → ship |
| Bug fix / debug / broken | bug-fix | debug → build → review → ship |
| Refactor / restructure | refactor | explore → design → plan → build → review → ship |
| Deploy / release | deploy | verify → ship → deploy |
| Research / explore | research | explore → research |
| Review / audit | review | review |

### Phase-Aware Context

The hook detects the current phase from session state:
- No plan file → enforce design phase (present approaches via AskUserQuestion)
- Plan exists, no commits → build phase (show task progress)
- Commits exist, no review → review phase (present review findings)
- Review done, not merged → ship phase (offer PR/merge/cleanup options)

This means the agent always knows where it is in the workflow and what interaction the user needs next.

### Visual Companion Integration

For brainstorming and frontend design, the visual companion provides a localhost server that displays:
- Architecture diagrams
- UI mockups with clickable option selection
- Side-by-side comparisons
- Design system previews

The server watches a content directory, serves the newest HTML file, and records user clicks to an events file. The agent writes HTML fragments (the server wraps them in a styled frame), reads the user's selections, and incorporates them into the next step.

This gives claudetools the same visual brainstorming capability superpowers has, natively integrated into the workflow.

---

## Summary: What Makes This Better Than Superpowers

| Dimension | Superpowers | Claudetools v6 |
|-----------|------------|----------------|
| **User interaction** | Must invoke `/brainstorm` manually | Agent-led: auto-detects intent, presents decisions with rich previews, user steers |
| Process depth | 150-280 LOC per skill | 170-250 LOC per skill (comparable) |
| Infrastructure | None | Codebase-pilot, metrics, agent-mesh |
| Enforcement | Model compliance only | Validators as real-time safety net |
| Feedback loop | None | Validator fires → process skipped → measurable |
| Project awareness | None | detect-project, codebase-pilot, memory |
| Memory | None | Episodic memory for past decisions |
| **CI/CD** | None | PR creation, CI monitoring, deploy, rollback |
| **Phase detection** | None | Auto-detects current phase from session state |
| Hook interface | 1 hook | 12 hooks (reduced from 54) |
| Multi-agent | Dispatch + review | Dispatch + review + mesh coordination |
| Self-improvement | None | health-report, plugin-improver, telemetry |

**The thesis:** Process + Tooling + Enforcement + Interaction Design > Process alone.

A user installs claudetools and gets a senior engineer that:
- Walks you through decisions with rich interactive previews
- Researches before building
- Designs before coding, showing you options visually
- Tests before implementing
- Verifies before claiming, shows evidence
- Reviews before shipping, presents findings
- Creates PRs, monitors CI, reports results
- Learns from every session
- Gets better over time

The agent leads. The user steers. Every decision is interactive, never silent.
