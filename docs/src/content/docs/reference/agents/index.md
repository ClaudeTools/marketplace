---
title: "Agents"
description: "11 specialized agents — 4 full-cycle pipelines (feature, bugfix, security, refactor) plus 7 standalone agents for targeted tasks."
---
11 specialized agents, including 4 full-cycle pipelines that compose skills into end-to-end workflows.

## Which agent should I use?

| Scenario | Recommended Agent | Why |
|----------|------------------|-----|
| Building a new feature end-to-end | [Feature Pipeline](/marketplace/reference/agents/feature-pipeline/) | Orchestrates exploration, planning, implementation, review, and verification in sequence |
| Fixing a bug with reproducible evidence | [Bugfix Pipeline](/marketplace/reference/agents/bugfix-pipeline/) | Enforces the full 6-step debugging protocol with structured review before closing |
| Auditing the codebase for security issues | [Security Pipeline](/marketplace/reference/agents/security-pipeline/) | Read-only — runs full audit, scan, dead-code analysis, and dep check without touching files |
| Refactoring shared or cross-cutting code | [Refactor Pipeline](/marketplace/reference/agents/refactor-pipeline/) | Impact analysis first, then decomposed implementation with regression verification |
| Making multi-file code changes | [Implementing Features](/marketplace/reference/agents/implementing-features/) | Full tool access; use when you have a clear plan and need focused execution |
| Reviewing code quality without changing it | [Code Reviewer](/marketplace/reference/agents/code-reviewer/) | Read-only 4-pass review — correctness, security, performance, maintainability |
| Generating tests for new or changed code | [Test Writer](/marketplace/reference/agents/test-writer/) | Follows existing project test patterns; generates targeted coverage |
| Researching external APIs or libraries | [Researcher](/marketplace/reference/agents/researcher/) | Read-only; fetches docs and returns actionable findings before you write integration code |
| Designing system architecture or APIs | [Architect](/marketplace/reference/agents/architect/) | Opus-powered read-only agent for design decisions, trade-off analysis, and impact review |
| Debugging without a full pipeline | [Investigating Bugs](/marketplace/reference/agents/investigating-bugs/) | Standalone debug agent — same protocol as the bugfix pipeline, without the review/confirm phases |
| Understanding unfamiliar code | [Exploring Codebase](/marketplace/reference/agents/exploring-codebase/) | Read-only; maps architecture, traces imports, and answers structural questions from the semantic index |

---

## Pipelines

| Agent | Flow | Use when |
|-------|------|----------|
| [Feature Pipeline](/reference/agents/feature-pipeline/) | explore &rarr; plan &rarr; implement &rarr; review &rarr; verify | Building a new feature |
| [Bugfix Pipeline](/reference/agents/bugfix-pipeline/) | explore &rarr; investigate &rarr; fix &rarr; review &rarr; confirm | Evidence-based bug resolution |
| [Security Pipeline](/reference/agents/security-pipeline/) | audit &rarr; scan &rarr; dead-code &rarr; deps &rarr; report | Read-only security assessment |
| [Refactor Pipeline](/reference/agents/refactor-pipeline/) | impact &rarr; decompose &rarr; implement &rarr; verify | Safe refactoring |

## Standalone Agents

| Agent | Model | Access | Purpose |
|-------|-------|--------|---------|
| [Architect](/reference/agents/architect/) | Opus | Read-only | Design decisions, impact analysis |
| [Implementing Features](/reference/agents/implementing-features/) | Sonnet | Full | Multi-file code changes |
| [Code Reviewer](/reference/agents/code-reviewer/) | Sonnet | Read-only | Quality review |
| [Test Writer](/reference/agents/test-writer/) | Sonnet | Full | Test generation |
| [Researcher](/reference/agents/researcher/) | Sonnet | Read-only | External API/library research |
| [Investigating Bugs](/reference/agents/investigating-bugs/) | Sonnet | Full | Evidence-based debugging |
| [Exploring Codebase](/reference/agents/exploring-codebase/) | Sonnet | Read-only | Codebase analysis |

---

## Related

- [Which Tool Should I Use?](/guides/which-tool/) — decision guide for choosing between skills, commands, and agents
- [Reference: Skills](/reference/skills/) — auto-triggered workflow skills that agents rely on
- [Core Concepts — Agents](/getting-started/core-concepts/#agents) — how agents, pipelines, and teammates relate
