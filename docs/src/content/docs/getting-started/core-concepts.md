---
title: "Core Concepts"
description: "The building blocks of claudetools — hooks, validators, skills, agents, codebase-pilot, and more — explained with analogies and a full glossary."
sidebar:
  order: 3
---

The eight building blocks of claudetools, what they do, why they matter, and how they connect.

---

## How it fits together

```
┌─────────────────────────────────────────────────────────────────┐
│                          Claude Code                            │
│                                                                 │
│  User types a prompt                                            │
│       ↓                                                         │
│  [UserPromptSubmit hooks]  ← inject context, memory, mesh msgs  │
│       ↓                                                         │
│  Claude decides a tool call                                     │
│       ↓                                                         │
│  [PreToolUse hooks]  ← safety check, read-before-edit, scope   │
│       ↓          ↓                                              │
│  BLOCK / WARN    ↓ PASS                                         │
│              Dispatcher → Validators → Gate decision            │
│                    ↓                                            │
│               Tool executes (Edit, Bash, Read…)                 │
│                    ↓                                            │
│  [PostToolUse hooks]  ← track reads/edits, reindex, telemetry  │
│                    ↓                                            │
│  Skills trigger (investigating-bugs, exploring-codebase…)       │
│  Agents orchestrate (feature-pipeline, bugfix-pipeline…)        │
│  Codebase Pilot answers structural queries from the index       │
└─────────────────────────────────────────────────────────────────┘
```

Hooks fire invisibly on every tool call. Skills and agents build structured workflows on top. The sections below explain each building block in detail.

---

## Hooks

**51 hooks across 17 lifecycle events.**

Hooks run automatically on every tool call. You don't invoke them — they fire invisibly, like security cameras that are always on. There are four categories:

| Category | What it covers |
|----------|---------------|
| **Safety** | Destructive commands, hardcoded secrets, sensitive file access |
| **Quality** | Stubs and placeholders, `as any` type abuse, edit churn detection |
| **Process** | Read-before-edit enforcement, commit hygiene, scope discipline |
| **Context** | Redundant read prevention, memory injection, session telemetry |

Hooks can block, warn, or annotate. Safety hooks always run. Non-safety hooks can be suppressed with `CLAUDE_HOOKS_QUIET=1`.

**Analogy:** Hooks are airport security checkpoints. You don't think about them when you walk to the gate — but they silently scan every bag. If something dangerous appears, you're stopped. Otherwise you pass through without friction.

**Why this matters:** Without hooks, Claude operates on trust and good intentions. With hooks, every edit, every commit, and every destructive command passes through a consistent policy layer. You get the same guardrails in a 2am emergency fix as in a calm morning refactor.

<details>
<summary>How are hooks implemented? (Advanced)</summary>

Each hook is a bash script in `plugin/hooks/`. When a lifecycle event fires (e.g., `PreToolUse`), Claude Code runs the matching scripts sequentially and reads their stdout/exit codes:

- **Exit 0** — pass, no output shown
- **Exit 0 with JSON** — warning or annotation shown to Claude
- **Exit 2** — block the tool call (hard stop)

The hook receives the tool name and arguments as JSON on stdin. Safety hooks read this to detect patterns like `rm -rf`, hardcoded API keys, or edits to `.env` files. The dispatcher routes each event to the appropriate hook scripts based on the tool name and event type.

</details>

**Reference:** [Hooks →](/reference/hooks/)

---

## Validators

Validators are pre-execution checks that run before a specific tool fires. Unlike hooks (which intercept any tool call), validators are attached to a named tool and enforce constraints specific to that operation.

**Analogy:** Validators are building code inspectors. Before a wall goes up, the inspector checks the blueprint against the local code — not because the builder is careless, but because the rules exist for a reason and must be verified independently.

**Why this matters:** Validators catch problems at the decision point, before any work happens. A hook that fires after a destructive command runs is too late. Validators stop the wrong action before it starts.

**Reference:** [Validators →](/advanced/validators/)

---

## Skills

**7 intelligent workflows.**

Skills are triggered automatically when your task matches, or explicitly via `/skill-name`. Think of them as specialist consultants you can call on demand — each one brings a specific methodology, not just a tool.

| Skill | Purpose |
|-------|---------|
| `/exploring-codebase` | Semantic navigation: find symbols, trace imports, map architecture, detect dead code |
| `/investigating-bugs` | 6-step evidence-based debugging protocol with two-strike rule |
| `/prompt-improver` | Transform rough instructions into structured XML prompts |
| `/frontend-design` | Production UI with design systems, responsive screenshots, contrast auditing |
| `/managing-tasks` | Persistent tasks with cross-session continuity |
| `/evaluating-safety` | Training scenarios, deterministic tests, cross-model safety comparison |
| `/plugin-improver` | 7-phase autonomous self-improvement with automatic regression revert |

**Analogy:** Skills are like specialist doctors in a hospital. A GP can handle most things, but when you need a structured debugging protocol or a UI design review, you consult the specialist who knows the exact methodology — not just the general approach.

**Why this matters:** Skills encode hard-won process knowledge. `/investigating-bugs` doesn't just say "look for the bug" — it enforces reproduce, observe, hypothesize, verify, fix, confirm. That structure prevents the common failure mode of fixing symptoms without confirming root cause.

**Reference:** [Skills →](/reference/skills/)

---

## Slash Commands

**8 explicit utility commands.**

Unlike skills, these don't auto-trigger. You invoke them when you want them — think of them as power tools hanging on the wall, not the automatic safety systems.

| Command | Purpose |
|---------|---------|
| `/session-dashboard` | Hook metrics, tool success rates, edit churn, token efficiency |
| `/memory` | Manage cross-session knowledge with FTS5 search and decay |
| `/code-review` | 4-pass structured review: correctness, security, performance, maintainability |
| `/field-review` | Plugin self-audit from real session data |
| `/logs` | Query conversation history, tool usage, and errors across sessions |
| `/docs-manager` | Documentation audit: staleness, indexing, archiving |
| `/claude-code-guide` | Best practices for building Claude Code extensions |
| `/mesh` | Agent coordination: file locks, messages, shared decisions |

**Analogy:** Slash commands are like the control panel in a car — the dashboard, the lights, the mirrors. The engine runs without them. But when you need to see what's happening, or check a specific reading, you reach for the right control.

**Why this matters:** Observability is optional until it isn't. `/session-dashboard` and `/logs` give you structured visibility into what Claude is actually doing, which is essential for catching drift, auditing decisions, and understanding token spend over time.

---

## Agents

**11 agents: 4 pipelines and 7 standalone.**

Agents are specialized subprocesses that Claude launches to handle complex tasks autonomously. They have their own tool access profiles — some read-only, some full access — and they return results when done.

Pipelines compose multiple agents into end-to-end workflows:

| Pipeline | Flow | Use when |
|----------|------|----------|
| `feature` | explore → plan → implement → review → verify | Building a new feature |
| `bugfix` | explore → investigate → fix → review → confirm | Evidence-based bug resolution |
| `security` | audit → scan → dead-code → deps → report | Read-only security assessment |
| `refactor` | impact → decompose → implement → verify | Safe refactoring |

Standalone agents handle targeted tasks:

| Agent | Access | Purpose |
|-------|--------|---------|
| `architect` | Read-only | Design decisions, impact analysis |
| `implementing-features` | Full | Multi-file code changes |
| `code-reviewer` | Read-only | Quality review |
| `test-writer` | Full | Test generation |
| `researcher` | Read-only | External API/library research |
| `investigating-bugs` | Full | Evidence-based debugging |
| `exploring-codebase` | Read-only | Codebase analysis and navigation |

**Analogy:** Agents are like project subcontractors. You (the general contractor) define the scope and constraints. Each specialist brings their own tools and expertise, works independently within those constraints, and reports back when done. The `exploring-codebase` agent only reads — it can't accidentally write a file while it's trying to understand one.

**Why this matters:** Pipelines enforce process. Instead of asking Claude to "build this feature", the `feature` pipeline ensures exploration happens before planning, planning before implementation, implementation before review. You get structured quality, not best-effort quality.

**Reference:** [Agents →](/reference/agents/)

---

## Rules

**10 behavioral guardrails.**

Rules are loaded by file path and govern how Claude behaves at a policy level — independent of hooks. They cover scope discipline, commit conventions, when to ask vs. act, and similar behavioral constraints.

**Analogy:** Rules are like an employment contract. Hooks are the security system that prevents certain actions. Rules are the policies that shape behavior — they don't block specific commands, they define the expected approach to the whole job.

**Why this matters:** Rules provide consistency across sessions. A rule that says "always read a file before editing it" or "use conventional commits" applies in every session without needing to be stated again. It's policy, not reminder.

**Reference:** [Rules →](/reference/rules/)

---

## Codebase Pilot

Tree-sitter + SQLite indexing engine. Builds a semantic index of your project at session start and updates it automatically as you edit files (via hooks).

Supports 14 languages: TypeScript, JavaScript, Python, Go, Rust, Java, Kotlin, Ruby, C#, PHP, Swift, C/C++, Bash, and more.

Key operations:

```bash
codebase-pilot map                        # Project overview
codebase-pilot find-symbol "handleAuth"   # Locate any symbol
codebase-pilot change-impact "handleAuth" # What breaks if this changes?
codebase-pilot dead-code                  # Unused exports
codebase-pilot circular-deps             # Circular import detection
```

The `exploring-codebase` skill and hooks both query this index. It's what makes navigation answers grounded in actual code rather than pattern matching on filenames.

**Analogy:** Codebase Pilot is like a city's GIS database. Without it, Claude navigates by memory and guesswork — "the post office is probably near the town square." With it, every query returns a precise address. The index is what separates "I think the auth handler is somewhere in middleware" from "it's at `src/middleware/auth.ts:47`."

**Why this matters:** Hallucinated file paths and function names waste time and produce incorrect analysis. Codebase Pilot grounds every symbol query, import trace, and change-impact analysis in the actual current state of your codebase.

<details>
<summary>How does codebase-pilot build its index? (Advanced)</summary>

At session start, `session-index.sh` runs `codebase-pilot index` against your project root. It uses tree-sitter grammars for each supported language to parse source files into syntax trees, then extracts:

- **Declarations** — function names, class names, exported symbols, with file path and line number
- **Import/export edges** — which file imports which symbol from which file
- **Call sites** — where each symbol is referenced (for `find-usages` and `change-impact`)

The extracted data is written to a SQLite database at `.codebase-pilot/index.db`. On subsequent sessions, only files modified since the last index run are re-parsed (incremental update via file modification timestamps). The index is local — it is never uploaded or shared.

When you edit a file, a `PostToolUse` hook calls `codebase-pilot reindex <file>` to update just that file's entries, keeping the index current throughout the session.

</details>

**Reference:** [Codebase Pilot →](/reference/codebase-pilot/indexing/)

---

## Agent Mesh

Multi-agent coordination layer for sessions where multiple Claude agents work the same repo simultaneously (via git worktrees).

Key operations via `plugin/agent-mesh/cli.js`:

- **List active agents** — see who's working and where
- **Lock files** — claim exclusive access before a multi-file refactor
- **Send messages** — alert other agents when your work affects shared files
- **Share context** — broadcast architectural decisions (auth strategy, test framework, etc.)

Without the mesh, parallel agents can produce conflicting edits. With it, they coordinate through locks and messages without manual intervention.

**Analogy:** The Agent Mesh is like an air traffic control system. Multiple planes (agents) can occupy the same airspace (codebase), but only because ATC (the mesh) manages separation, priorities, and communication. Without it, parallel agents are flying blind in the same corridor.

**Why this matters:** As soon as two agents touch the same codebase, you have a distributed systems problem. The mesh brings the coordination primitives — locks, messages, shared context — that prevent the silent merge conflicts and architectural drift that happen when agents work in isolation.

**Reference:** [Agent Mesh →](/reference/agent-mesh/)

---

## Task System

MCP-based persistent task tracking. Tasks survive across sessions and can be decomposed into subtasks.

The `/managing-tasks` skill exposes the full interface: `new`, `start`, `stop`, `status`, `restore`, `decompose`, `progress`, `handoff`, `validate`.

Tasks created here are accessible from any session in the same project directory.

**Analogy:** The Task System is like a shared Kanban board that never closes. Sticky notes on a whiteboard disappear when the session ends. The Task System persists — every task, every subtask, every status update survives context compaction and session restarts.

**Why this matters:** Long-running work fragments across sessions. Without persistent tasks, you re-explain context every time you restart. With the Task System, a session handoff is a structured document, not a conversation recap, and work continues without re-orientation.

**Reference:** [Task System →](/reference/task-system/)

---

## Glossary

Quick reference for every term used across the claudetools documentation.

---

**agent**
: A specialized subprocess launched by Claude to handle a complex task autonomously. Agents have constrained tool access (read-only or full) and return results when done. See [Agents →](/reference/agents/)

**agent mesh**
: The multi-agent coordination layer that manages file locks, inter-agent messaging, and shared context when multiple Claude sessions work the same repository simultaneously. See [Agent Mesh →](/reference/agent-mesh/)

**CLAUDE.md**
: A markdown file committed to a repository that injects persistent instructions into every Claude session. Used to encode project conventions, rules, and behavioral policies. Global CLAUDE.md lives in `~/.claude/`.

**codebase-pilot**
: The Tree-sitter + SQLite semantic indexing engine. Builds and queries a symbol index of your project, used by hooks and skills for grounded navigation and analysis. See [Codebase Pilot →](/reference/codebase-pilot/indexing/)

**dispatcher**
: The internal routing layer that decides which hook, validator, or skill handles a given event. It evaluates the incoming tool call or lifecycle event and selects the appropriate handler.

**gate**
: A blocking check in the dispatcher chain. If a gate returns false, the tool call is prevented. Gates are how safety hooks enforce hard stops.

**hook**
: A shell script that fires automatically on a lifecycle event (e.g., `PreToolUse`, `SessionStart`). Hooks can block, warn, or annotate without being explicitly called. See [Hooks →](/reference/hooks/)

**lifecycle event**
: A named moment in a Claude session when hooks can fire — e.g., `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `WorktreeCreate`. There are 17 lifecycle events in claudetools. See [Hooks →](/reference/hooks/)

**MCP**
: Model Context Protocol — the standard that Claude Code uses to communicate with external servers. The Task System, codebase-pilot, and agent mesh are all MCP servers. See [Task System →](/reference/task-system/)

**pipeline**
: A multi-stage agent that composes skills and standalone agents into an end-to-end workflow. The `feature` pipeline, for example, runs explore → plan → implement → review → verify in sequence. See [Agents →](/reference/agents/)

**skill**
: A structured workflow that Claude activates automatically when a task matches, or on demand via `/skill-name`. Skills encode specific methodologies (debugging protocols, UI review checklists) as reusable processes. See [Skills →](/reference/skills/)

**slash command**
: A user-invocable command prefixed with `/` that triggers a utility operation (e.g., `/session-dashboard`, `/code-review`). Unlike skills, slash commands do not auto-trigger.

**task system**
: The MCP-based persistent task tracker. Tasks survive session restarts and context compaction; subtasks can be decomposed; state is committed to `.tasks/`. See [Task System →](/reference/task-system/)

**tool call**
: A single invocation of a Claude Code tool — e.g., `Read`, `Edit`, `Bash`, `Write`. Hooks fire on `PreToolUse` and `PostToolUse` around every tool call.

**validator**
: A pre-execution constraint attached to a specific tool. Validators run before the tool fires and can block the operation based on the arguments or current state. See [Validators →](/advanced/validators/)

**worktree**
: A git feature that allows multiple branches to be checked out simultaneously in separate directories. claudetools uses worktrees to let multiple agents work the same repository in parallel without interfering with each other.

---

## Related

- [Quick Tour](quick-tour.md) — see hooks, skills, and the session dashboard working in real scenarios
- [Installation](installation.md) — install claudetools and verify hooks are running
- [Hooks Reference](/reference/hooks/) — complete index of all 51 hooks across 17 lifecycle events
