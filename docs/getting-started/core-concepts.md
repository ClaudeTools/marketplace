---
title: Core Concepts
parent: Getting Started
nav_order: 3
---

# Core Concepts

The building blocks of claudetools and how they fit together.

---

## Hooks

**51 hooks across 17 lifecycle events.**

Hooks run automatically on every tool call. You don't invoke them — they fire invisibly as guardrails. There are four categories:

| Category | What it covers |
|----------|---------------|
| **Safety** | Destructive commands, hardcoded secrets, sensitive file access |
| **Quality** | Stubs and placeholders, `as any` type abuse, edit churn detection |
| **Process** | Read-before-edit enforcement, commit hygiene, scope discipline |
| **Context** | Redundant read prevention, memory injection, session telemetry |

Hooks can block, warn, or annotate. Safety hooks always run. Non-safety hooks can be suppressed with `CLAUDE_HOOKS_QUIET=1`.

---

## Skills

**7 intelligent workflows.**

Skills are triggered automatically when your task matches, or explicitly via `/skill-name`.

| Skill | Purpose |
|-------|---------|
| `/exploring-codebase` | Semantic navigation: find symbols, trace imports, map architecture, detect dead code |
| `/investigating-bugs` | 6-step evidence-based debugging protocol with two-strike rule |
| `/improving-prompts` | Transform rough instructions into structured XML prompts |
| `/designing-interfaces` | Production UI with design systems, responsive screenshots, contrast auditing |
| `/managing-tasks` | Persistent tasks with cross-session continuity |
| `/evaluating-safety` | Training scenarios, deterministic tests, cross-model safety comparison |
| `/improving-plugin` | 7-phase autonomous self-improvement with automatic regression revert |

---

## Slash Commands

**8 explicit utility commands.**

Unlike skills, these don't auto-trigger. You invoke them when you want them.

| Command | Purpose |
|---------|---------|
| `/session-dashboard` | Hook metrics, tool success rates, edit churn, token efficiency |
| `/memory` | Manage cross-session knowledge with FTS5 search and decay |
| `/code-review` | 4-pass structured review: correctness, security, performance, maintainability |
| `/field-review` | Plugin self-audit from real session data |
| `/logs` | Query conversation history, tool usage, and errors across sessions |
| `/docs-manager` | Documentation audit: staleness, indexing, archiving |
| `/claude-code-guide` | Best practices for building Claude Code extensions |

---

## Agents

**11 agents: 4 pipelines and 7 standalone.**

Pipelines compose skills into end-to-end workflows:

| Pipeline | Flow |
|----------|------|
| `feature` | explore → plan → implement → review → verify |
| `bugfix` | explore → investigate → fix → review → confirm |
| `security` | audit → scan → dead-code → deps → report |
| `refactor` | impact → decompose → implement → verify |

Standalone agents: `architect`, `implementing-features`, `code-reviewer`, `test-writer`, `researcher`, `investigating-bugs`, and one more.

---

## Rules

**10 behavioral guardrails.**

Rules are loaded by file path and govern how Claude behaves at a policy level — independent of hooks. They cover scope discipline, commit conventions, when to ask vs. act, and similar behavioral constraints.

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

The exploring-codebase skill and hooks both query this index. It's what makes navigation answers grounded in actual code rather than pattern matching on filenames.

---

## Agent Mesh

Multi-agent coordination layer for sessions where multiple Claude agents work the same repo simultaneously (via git worktrees).

Key operations via `plugin/agent-mesh/cli.js`:

- **List active agents** — see who's working and where
- **Lock files** — claim exclusive access before a multi-file refactor
- **Send messages** — alert other agents when your work affects shared files
- **Share context** — broadcast architectural decisions (auth strategy, test framework, etc.)

Without the mesh, parallel agents can produce conflicting edits. With it, they coordinate through locks and messages without manual intervention.

---

## Task System

MCP-based persistent task tracking. Tasks survive across sessions and can be decomposed into subtasks.

The `/managing-tasks` skill exposes the full interface: `new`, `start`, `stop`, `status`, `restore`, `decompose`, `progress`, `handoff`, `validate`.

Tasks created here are accessible from any session in the same project directory.
