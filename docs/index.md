---
title: Home
layout: home
nav_order: 1
permalink: /
---

# claudetools

Zero-config guardrails, skills, and agent pipelines for Claude Code.
{: .fs-9 }

51 hooks across 17 lifecycle events. 7 intelligent skills. 11 specialized agents. Semantic codebase navigation across 14 languages.
{: .fs-6 .fw-300 }

[Get Started](/getting-started/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/ClaudeTools/marketplace){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Install

```
/plugin install claudetools@claudetools-marketplace
```

Hooks activate immediately. Skills available via `/skill-name`. No configuration needed.

---

## What's included

### Guardrail Hooks

51 hooks in 4 categories — safety, quality, process, context. They run automatically on every tool call, catching destructive commands, stubs, uncommitted work, and redundant operations before they cause problems.

### Intelligent Skills

7 workflow skills that Claude triggers automatically when your task matches, or you invoke directly via `/skill-name`. Structured debugging, codebase exploration, prompt engineering, UI design, task management, safety evaluation, and self-improvement.

### Agent Pipelines

4 full-cycle pipelines (feature, bugfix, security, refactor) that orchestrate multiple skills into end-to-end workflows. Plus 7 standalone agents: architect, code-reviewer, test-writer, researcher, implementing-features, investigating-bugs, exploring-codebase.

### Codebase Pilot

Tree-sitter + SQLite semantic indexing engine. Parses your codebase into a queryable database of symbols, imports, and file relationships. 14 languages: TypeScript, JavaScript, Python, Go, Rust, Java, Kotlin, Ruby, C#, PHP, Swift, C, C++, Bash.

---

## Common workflows

| Guide | What you'll do |
|-------|----------------|
| [Debug a Bug](/guides/debug-a-bug/) | Follow the evidence-based 6-step protocol: reproduce, observe, hypothesize, verify, fix, confirm |
| [Build a Feature](/guides/build-a-feature/) | End-to-end pipeline from task creation through implementation to verified delivery |
| [Explore a Codebase](/guides/explore-a-codebase/) | Navigate unfamiliar code with semantic search, import tracing, and architecture mapping |
| [Review Code](/guides/review-code/) | Structured 4-pass review covering correctness, security, performance, and maintainability |
| [Coordinate Agents](/guides/coordinate-agents/) | Multi-agent work with file locking, message passing, and shared decisions |

---

## Requirements

Claude Code v1.0+ &bull; Node.js 18+ &bull; SQLite3 &bull; jq (recommended)
