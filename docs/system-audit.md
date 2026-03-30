# System Audit: Five-Step Algorithm Applied to the Full Plugin

> The claudetools plugin is a reactive enforcement system. The superpowers plugin is a proactive constraint system. One catches problems after they happen. The other prevents them from happening. This audit applies the Five-Step Algorithm to close that gap.

---

## The Two Architectures

**Claudetools** (this plugin):
- 49 hook chains across 16 event types
- 27 validators, 13 shared libraries
- 15 skills (7 documented)
- 3-level memory system (FTS index → extraction → AI reflection)
- Dual-track task system (TodoWrite + native tasks)
- Codebase-pilot indexer (30s at SessionStart)
- Agent mesh for multi-session coordination
- SQLite metrics database (8 tables)
- ~4,800 LOC hooks + ~3,200 LOC validators + infrastructure

**Superpowers** (reference model):
- 1 hook (SessionStart: inject using-superpowers skill)
- 0 validators
- 14 skills forming a mandatory workflow chain
- 1 agent definition (code-reviewer)
- ~19K LOC (almost entirely skill documentation)
- Zero databases, zero telemetry infrastructure

**Superpowers achieves comparable or better agent quality with 1/50th the hook infrastructure.** The question is: why?

---

## Step 1: Question

### Why does superpowers work with zero validators?

Superpowers prevents problems that claudetools detects after the fact. Compare:

| Problem | Claudetools (reactive) | Superpowers (proactive) |
|---------|----------------------|------------------------|
| Agent writes stubs | `stubs.sh` validator blocks Edit/Write | TDD skill: no production code without failing test first |
| Agent skips design | No prevention | Brainstorming skill: HARD GATE blocks all implementation until design approved |
| Agent claims "should work" | `session-stop-gate.sh` detects weasel phrases | Verification skill: "no completion claims without fresh verification evidence" |
| Agent over-engineers | `task-scope.sh` warns on scope creep | Writing-plans skill: bite-sized tasks with clear acceptance criteria |
| Agent edits without reading | `blind-edit.sh` warns | Not needed — skills structure work to always read first |
| Agent adds unwanted deps | `unasked-deps.sh` warns | Writing-plans skill: dependencies listed in plan, approved upfront |

**The pattern:** Claudetools validators are compensating for the absence of upstream process constraints. Superpowers makes those constraints mandatory at the skill level, so the downstream validators become unnecessary.

### Which validators are genuinely reactive (can't be prevented)?

Some validators catch problems that no upstream process can prevent:

- **dangerous-bash.sh** — Agent might construct a dangerous command at any time. Must be caught in real-time.
- **secrets.sh** — Hardcoded credentials can appear anywhere. Must be caught on write.
- **guard-sensitive-files.sh** — File access control. Deterministic gate.
- **enforce-user-stop.sh** — User override. Must always work.
- **guard-context-reread.sh** — Context efficiency. Deterministic.

These are **genuine Tier 1 safety gates** — deterministic, zero-cost, always needed.

### Which validators are compensating for missing process?

- **stubs.sh** — Compensates for no TDD requirement
- **blind-edit.sh** — Compensates for no read-before-write process
- **task-scope.sh** — Compensates for no upfront planning
- **unasked-deps.sh** — Compensates for no dependency approval in plans
- **unasked-restructure.sh** — Compensates for no restructuring approval in plans
- **prefer-edit-over-write.sh** — Compensates for no tool-selection process
- **weasel phrase detection** — Compensates for no verification-before-completion process
- **ran-checks.sh** — Compensates for no TDD/verification requirement
- **no-deferred-actions.sh** — Compensates for no task completion criteria
- **research-backing.sh** — Compensates for no research-first process

These validators exist because the plugin doesn't enforce the right process upstream. If skills enforced brainstorming → planning → TDD → verification (like superpowers does), most of these validators would fire zero times.

### Does the 3-level memory system justify its complexity?

- **Level 1 (FTS index):** Deterministic, fast, useful. Keep.
- **Level 2 (extract-fast):** Deterministic grep, async, cheap. Keep.
- **Level 3 (memory-reflect):** Two sequential Sonnet calls (30-90s), async, sometimes times out silently. **Question: what's the success rate? How often do reflected memories actually get recalled and used?**

If Level 3 memories aren't recalled at a meaningful rate, the two Sonnet calls per session are waste.

### Does codebase-pilot need 30s at SessionStart?

The 30s codebase-pilot index runs at every SessionStart. For a returning user working on the same codebase, the index is already built. **Question: can indexing be incremental (only re-index changed files) instead of full-rebuild?**

### Does the dual-track task system add value?

- Track 1: TodoWrite → on-todo-write.js → .tasks/tasks.json
- Track 2: TaskCreate/TaskUpdate (native Claude tools) → track-native-tasks.sh

Two systems tracking the same concept. **Question: can we use only native tasks and drop the TodoWrite track?**

---

## Step 2: Delete

### Tier 1 — Delete validators that skills should prevent

If the plugin adopted superpowers-style mandatory skill invocation, these validators become dead code:

| Validator | Prevented by | Action |
|-----------|-------------|--------|
| `stubs.sh` (PostToolUse) | TDD skill: no code without failing test | Keep as safety net, downgrade from block to warn |
| `blind-edit.sh` | Read-before-write built into skill workflows | Delete |
| `task-scope.sh` | Planning skill: acceptance criteria define scope | Delete |
| `unasked-deps.sh` | Planning skill: dependencies approved in plan | Delete |
| `prefer-edit-over-write.sh` | Tool routing in skill instructions | Delete |
| `no-deferred-actions.sh` | Verification skill: must complete, not defer | Delete |
| `ran-checks.sh` | TDD/verification skill: tests run before completion | Delete |
| `research-backing.sh` | Research-first step in planning skill | Downgrade to warn |

**Estimated reduction: 8 validators (~800 LOC), leaving 19 validators.**

### Tier 2 — Delete telemetry that isn't consumed

Before deleting any telemetry, answer: **who reads this data?**

| Component | What it produces | Who consumes it? |
|-----------|-----------------|-----------------|
| `capture-outcome.sh` | tool_outcomes table | session-dashboard skill, threshold tuning |
| `capture-failure.sh` | failure events | failure-pattern-detector |
| `track-file-reads.sh` | read JSONL | guard-context-reread, edit-frequency-guard |
| `track-file-edits.sh` | edit JSONL + mesh notify | edit-frequency-guard, agent-mesh |
| `config-audit-trail.sh` | config change log | Nobody? |
| `doc-stale-detector.sh` | stale doc warnings | SessionStart only |
| `desktop-alert.sh` | OS notifications | User |

**Candidates for deletion:** `config-audit-trail.sh` (if nobody reads the log). Everything else has a consumer.

### Tier 3 — Delete the TodoWrite track

The native task system (TaskCreate/TaskUpdate) is the primary track. The TodoWrite integration adds complexity (on-todo-write.js, Node.js dependency) for a legacy interface. If native tasks are working, delete the TodoWrite hook and track.

---

## Step 3: Simplify

### Adopt superpowers' "mandatory skill invocation" pattern

The single most impactful change: make skill invocation non-optional for implementation work. Superpowers' `using-superpowers` meta-skill forces agents to check for applicable skills before ANY action.

Claudetools already has this hook (`UserPromptSubmit: inject-prompt-context.sh`). Strengthen it:

1. At UserPromptSubmit, classify the user's intent (Tier 1: keyword match)
2. If intent matches a skill (implementation → brainstorming + planning, debugging → debugger, etc.), inject a mandatory skill invocation instruction
3. The skill itself provides the process constraints that prevent problems

This replaces 8+ validators with upstream process.

### Simplify the memory system to 2 levels

- **Level 1 (FTS index):** Keep. Deterministic, useful, fast.
- **Level 2 (extract + reflect combined):** Merge the deterministic extraction and AI reflection into a single async hook that:
  1. Runs the fast deterministic extraction first
  2. Only invokes AI reflection if extraction found high-signal candidates
  3. Saves extracted candidates even if AI times out

This eliminates one hook and ensures the deterministic extraction is never lost to a timeout.

### Simplify codebase-pilot to incremental indexing

Instead of full rebuild at SessionStart (30s):
1. Check if index.db exists and is recent (< 1 hour old)
2. If yes, only index files changed since last index (git diff)
3. If no, full rebuild
4. Full rebuild on ConfigChange/WorktreeCreate (rare events)

Expected reduction: SessionStart from 60s to ~10s for returning sessions.

### Consolidate task system to native-only

Drop the TodoWrite → on-todo-write.js track. Use only native TaskCreate/TaskUpdate. Remove `on-todo-write.js` and its PostToolUse hook entry.

---

## Step 4: Accelerate

### Pre-compute shared state at SessionStart

Currently, every PreToolUse hook independently checks:
- Is this a git repo?
- What's the current branch?
- What files are changed?

With `lib/git-state.sh` (created in the hooks optimization), pre-compute this once and cache via exports. Extend this to SessionStart: compute git state once, make it available to all hooks in the session.

### Classify tool calls at the dispatcher level

Currently, each PreToolUse matcher runs its own chain. The dispatcher could classify the tool call once and route to the minimal validator set:

```
Tool: Bash
  → Is command in safe fast-path? → Allow (0ms)
  → Is command in dangerous patterns? → Block (1ms)
  → Otherwise → Run remaining validators

Tool: Edit/Write
  → Is file a test/doc/config? → Skip content validators (0ms)
  → Is file sensitive? → Block (1ms)
  → Otherwise → Run content validators
```

This is the Intelligence Spectrum applied to the hook system itself: Tier 1 routing before Tier 2/3 validation.

### Make SessionStart non-blocking for known projects

For returning sessions where codebase-pilot has a recent index:
1. Inject cached context immediately (< 1s)
2. Run incremental reindex in background (async)
3. Session is usable in < 5s instead of 60s

---

## Step 5: Automate

### Automate skill invocation (not skill execution)

The superpowers pattern: "If there's even a 1% chance a skill applies, invoke it." This should be automated in claudetools:

1. At UserPromptSubmit, match user intent against skill descriptions
2. Inject the matched skill's instructions into context
3. The agent follows the skill's process naturally

This is the equivalent of superpowers' SessionStart hook that injects `using-superpowers`, but applied to all skills.

### Automate validator health tracking

After deleting compensatory validators, the remaining ones are genuine safety gates. Automate tracking their effectiveness:

1. Record every block/warn decision
2. Track false positive rate (user overrides the block)
3. If a validator has >50% false positive rate, flag it for review
4. If a validator has 0% trigger rate over 30 days, flag it as potentially dead

This is the Intelligence Spectrum's Tier 3: use AI to evaluate whether the Tier 1 gates are correctly calibrated.

---

## The Superpowers Principle

Superpowers works because it applies three ideas that claudetools should adopt:

### 1. Constraints are features, not limitations

Every "you MUST" in superpowers saves cognitive load. The agent doesn't decide "should I TDD?" — the skill says "you must TDD." Removing the decision is more powerful than adding a validator that catches the wrong decision after the fact.

### 2. Prevention over detection

A skill that requires brainstorming before implementation prevents scope creep, missing requirements, and over-engineering. Three validators that detect these problems after implementation are slower, more expensive, and less effective.

### 3. Mandatory workflows, not optional tools

Superpowers' skills form a chain: brainstorm → plan → implement → verify. Skipping a step is explicitly called out as a violation, with rationalization tables that preempt common excuses. Claudetools' skills are available but optional — the agent decides whether to use them.

**The fundamental shift:** Move from "detect and block bad outcomes" to "constrain the process so bad outcomes can't happen." The hooks that remain should be genuine safety gates (secrets, dangerous commands, file access control) — not compensations for missing process.

---

## Summary: What Changes

| Area | Current | Proposed |
|------|---------|----------|
| **Validators** | 27 (catch everything) | 19 (safety gates only) |
| **Skills** | 15 (optional) | 15 (mandatory invocation for implementation) |
| **Memory levels** | 3 (FTS + extract + reflect) | 2 (FTS + combined extract/reflect) |
| **Task tracks** | 2 (TodoWrite + native) | 1 (native only) |
| **SessionStart** | 60s (full rebuild) | <10s (incremental + async reindex) |
| **Hook philosophy** | Reactive enforcement | Proactive constraints + safety gates |
| **LOC (validators)** | ~3,200 | ~2,400 |

The goal is not fewer lines of code. The goal is fewer decisions the agent has to make wrong before something catches it. The best validator is one that never fires because the process upstream made the violation impossible.
