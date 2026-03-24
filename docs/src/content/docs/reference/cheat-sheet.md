---
title: "Cheat Sheet"
description: "One-page scannable reference — all slash commands, skills, agents, hooks, and codebase-pilot commands."
sidebar:
  order: 2
---

Everything in one place. Click any item to jump to the full reference.

---

## Slash Commands

| Command | What it does | Example |
|---------|-------------|---------|
| [`/code-review`](commands/code-review.md) | 4-pass structured review: correctness, security, performance, maintainability | `/code-review feature/auth` |
| [`/memory`](commands/memory.md) | Add, view, remove, or export persistent cross-session developer preferences | `/memory add "Always use pnpm"` |
| [`/mesh`](commands/mesh.md) | Check active agents, lock files, send messages, share architectural decisions | `/mesh status` |
| [`/session-dashboard`](commands/session-dashboard.md) | Plugin health report — failure trends, churn rate, top failing tools | `/session-dashboard 20` |
| [`/docs-manager`](commands/docs-manager.md) | Init, audit, archive, or reindex project documentation | `/docs-manager audit` |
| [`/logs`](commands/logs.md) | Search session logs — tool usage, errors, side questions | `/logs error` |
| [`/field-review`](commands/field-review.md) | Performance review of the claudetools plugin itself — false positives, gaps | `/field-review` |
| [`/claude-code-guide`](commands/claude-code-guide.md) | Best practices reference for Claude Code extensions | `/claude-code-guide hooks` |

---

## Skills

Skills activate automatically when your prompt matches their trigger patterns, or invoke explicitly.

| Skill | Trigger | What it does |
|-------|---------|-------------|
| [Exploring Codebase](skills/exploring-codebase.md) | `/exploring-codebase` or "how does X work", "find where Y is defined" | Semantic navigation via codebase-pilot — find symbols, trace imports, map architecture |
| [Investigating Bugs](skills/investigating-bugs.md) | `/investigating-bugs` or "broken", "failing", "500", "why is" | 6-step evidence-based debugging: REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM |
| [Prompt Improver](skills/prompt-improver.md) | `/prompt-improver` or "improve this prompt" | Transforms vague instructions into structured XML prompts with approach blocks and escape clauses |
| [Frontend Design](skills/frontend-design.md) | `/frontend-design` or "build a UI", "design a dashboard" | Production UI with design systems, responsive layout, contrast auditing |
| [Managing Tasks](skills/managing-tasks.md) | `/managing-tasks` or "create a task", "what's next" | Persistent tasks with codebase context enrichment, decomposition, and cross-session handoffs |
| [Evaluating Safety](skills/evaluating-safety.md) | `/evaluating-safety` or "run training", "test safety" | Training scenarios, deterministic tests, cross-model safety comparison |
| [Plugin Improver](skills/plugin-improver.md) | `/plugin-improver` | 7-phase autonomous self-improvement of the claudetools plugin with automatic regression revert |

---

## Agents

Agents are spawned subprocesses. Pipelines compose multiple agents into end-to-end workflows.

### Pipelines

| Agent | Flow | Invoke when |
|-------|------|-------------|
| [Feature Pipeline](agents/feature-pipeline.md) | explore → plan → implement → review → verify | Building a new feature end-to-end |
| [Bugfix Pipeline](agents/bugfix-pipeline.md) | explore → investigate → fix → review → confirm | Evidence-based bug resolution with structured review |
| [Security Pipeline](agents/security-pipeline.md) | audit → scan → dead-code → deps → report | Read-only security assessment of the full codebase |
| [Refactor Pipeline](agents/refactor-pipeline.md) | impact → decompose → implement → verify | Safe refactoring of shared or cross-cutting code |

### Standalone Agents

| Agent | Model | Access | Best for |
|-------|-------|--------|----------|
| [Architect](agents/architect.md) | Opus | Read-only | Design decisions, API design, trade-off analysis |
| [Implementing Features](agents/implementing-features.md) | Sonnet | Full | Multi-file code changes with a clear plan |
| [Code Reviewer](agents/code-reviewer.md) | Sonnet | Read-only | Quality review without touching files |
| [Test Writer](agents/test-writer.md) | Sonnet | Full | Test generation following existing patterns |
| [Researcher](agents/researcher.md) | Sonnet | Read-only | External API/library research before integration |
| [Investigating Bugs](skills/investigating-bugs.md) | Sonnet | Full | Debugging without the full pipeline overhead |
| [Exploring Codebase](skills/exploring-codebase.md) | Sonnet | Read-only | Architecture mapping, import tracing |

---

## Hooks

51 hooks across 17 lifecycle events. See [Hooks reference](hooks/index.md) for full details.

### Safety Hooks

| Hook | When it fires | What it catches |
|------|--------------|----------------|
| `enforce-user-stop` | PreToolUse (all) | User stop signal — blocks all tools immediately |
| `guard-sensitive-files` | PreToolUse (Read, Edit, Write) | `.env`, `*.pem`, `*.key`, credential files |
| `pre-bash-gate` | PreToolUse (Bash) | `rm -rf`, force-push, curl-pipe-sh, credential-targeting commands |
| `block-dangerous-bash` | PreToolUse (Bash) | mkfs, fdisk, reverse shells, `chmod -R 777`, PATH clearing |
| `validate-content` | PostToolUse (Edit, Write) | Stubs, `TODO`/`FIXME`, `@ts-ignore`, `as any`, empty catch blocks |
| `guard-secrets` | PostToolUse (Edit, Write) | API keys, tokens, and credential patterns written into source |

### Quality Hooks

| Hook | When it fires | What it catches |
|------|--------------|----------------|
| `pre-edit-gate` | PreToolUse (Edit, Write) | Editing a file that hasn't been read — "read before editing" |
| `enforce-read-efficiency` | PreToolUse (Read) | Re-reading an unchanged file already in context |
| `edit-frequency-guard` | PostToolUse (Edit, Write) | Same file edited >3 times — trial-and-error signal |
| `post-agent-gate` | PostToolUse (Agent) | Subagent reported "done" without verifiable evidence |
| `verify-subagent-independently` | SubagentStop | Re-runs typecheck/tests independent of subagent self-report |
| `check-mock-in-prod` | PostToolUse (Edit, Write) | Hardcoded mock data or `Example Item 1` in production code |

### Process Hooks

| Hook | When it fires | What it catches |
|------|--------------|----------------|
| `require-active-task` | PreToolUse (Edit, Write) | Writing files without an active task |
| `enforce-team-usage` | PreToolUse (Agent) | Spawning agents without `TeamCreate` |
| `block-unasked-restructure` | PreToolUse (Edit, Write) | Unrequested project restructuring or file moves |
| `session-stop-gate` | Stop | Incomplete tasks, uncommitted changes, dangling work |
| `enforce-deploy-then-verify` | PostToolUse (Bash) | Deploy commands not followed by endpoint verification |
| `failure-pattern-detector` | PostToolUseFailure | 3 same-tool failures — blocks and forces approach change |

### Context Hooks

| Hook | When it fires | What it catches / provides |
|------|--------------|---------------------------|
| `inject-session-context` | SessionStart | Injects learned failure patterns from `metrics.db` |
| `inject-prompt-context` | UserPromptSubmit | Enriches every prompt with git state and active task |
| `capture-outcome` | PostToolUse | Records tool telemetry to `metrics.db` |
| `archive-before-compact` | PreCompact | Saves critical task state before context compaction |
| `restore-after-compact` | PostCompact | Re-injects saved state after compaction |
| `memory-reflect` | Stop | Extracts learnings and proposes memory additions |
| `config-audit-trail` | ConfigChange | Logs every settings change to JSONL audit trail |
| `doc-manager` | PostToolUse (Write) | Enforces doc naming, frontmatter, and modification dates |

---

## Codebase Pilot

Semantic code index built with tree-sitter + SQLite. Run commands via:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js <command>
```

| Command | Purpose | Example |
|---------|---------|---------|
| `index` | Build or update the full project index | `codebase-pilot index` |
| `index-file <path>` | Incremental reindex of a single file | `codebase-pilot index-file src/auth.ts` |
| `map` | Project overview: file count, languages, entry points, top symbols | `codebase-pilot map` |
| `find-symbol <name>` | FTS5 search for symbols by name (optional `--kind` filter) | `codebase-pilot find-symbol UserService --kind class` |
| `find-usages <name>` | All files that import a symbol | `codebase-pilot find-usages AuthMiddleware` |
| `file-overview <path>` | All symbols and imports in a file | `codebase-pilot file-overview src/routes/api.ts` |
| `related-files <path>` | Two-way import graph for a file | `codebase-pilot related-files src/services/user.ts` |
| `navigate <query>` | Multi-channel scored search (symbols + paths + imports) | `codebase-pilot navigate "rate limiting"` |
| `dead-code` | Exported symbols never imported anywhere | `codebase-pilot dead-code` |
| `change-impact <symbol>` | Files affected if this symbol's definition changes | `codebase-pilot change-impact UserService` |
| `context-budget` | Most-imported files ranked by frequency | `codebase-pilot context-budget` |
| `api-surface` | All exported symbols across the project | `codebase-pilot api-surface` |
| `circular-deps` | Detect circular import chains | `codebase-pilot circular-deps` |
| `doctor` | Health check — SQLite, grammars, index freshness | `codebase-pilot doctor` |

---

## Related

- [Common Recipes](../guides/recipes.md) — composite workflows combining these tools
- [Which Tool Should I Use?](../guides/which-tool.md) — decision tree
- [What's New](whats-new.md) — recent releases
