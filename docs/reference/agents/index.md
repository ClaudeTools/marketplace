---
title: Agents
parent: Reference
nav_order: 3
has_children: true
---

# Agents

11 specialized agents, including 4 full-cycle pipelines that compose skills into end-to-end workflows.

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
