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

[Get Started]({{ site.baseurl }}/getting-started/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
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

[Hooks Reference]({{ site.baseurl }}/reference/hooks/){: .btn .btn-outline .fs-3 }

### Intelligent Skills

7 workflow skills that Claude triggers automatically when your task matches, or you invoke directly via `/skill-name`. Structured debugging, codebase exploration, prompt engineering, UI design, task management, safety evaluation, and self-improvement.

[Skills Reference]({{ site.baseurl }}/reference/skills/){: .btn .btn-outline .fs-3 }

### Agent Pipelines

4 full-cycle pipelines (feature, bugfix, security, refactor) that orchestrate multiple skills into end-to-end workflows. Plus 7 standalone agents for architecture, code review, testing, research, implementation, debugging, and codebase exploration.

[Agents Reference]({{ site.baseurl }}/reference/agents/){: .btn .btn-outline .fs-3 }

### Codebase Pilot

Tree-sitter + SQLite semantic indexing engine. Parses your codebase into a queryable database of symbols, imports, and file relationships across 14 languages.

[Codebase Pilot Reference]({{ site.baseurl }}/reference/codebase-pilot/){: .btn .btn-outline .fs-3 }

---

## Common workflows

| Guide | What you'll do |
|-------|----------------|
| [Debug a Bug]({{ site.baseurl }}/guides/debug-a-bug/) | Evidence-based 6-step protocol: reproduce, observe, hypothesize, verify, fix, confirm |
| [Build a Feature]({{ site.baseurl }}/guides/build-a-feature/) | End-to-end pipeline from task creation through verified delivery |
| [Explore a Codebase]({{ site.baseurl }}/guides/explore-a-codebase/) | Semantic search, import tracing, and architecture mapping |
| [Review Code]({{ site.baseurl }}/guides/review-code/) | 4-pass review: correctness, security, performance, maintainability |
| [Coordinate Agents]({{ site.baseurl }}/guides/coordinate-agents/) | Multi-agent work with file locking and message passing |
| [Manage Tasks]({{ site.baseurl }}/guides/manage-tasks/) | Persistent tasks with cross-session continuity and handoff |
| [Improve Prompts]({{ site.baseurl }}/guides/improve-prompts/) | Transform rough instructions into structured, executable prompts |
| [Design a UI]({{ site.baseurl }}/guides/design-a-ui/) | Production UI with generated design systems and responsive testing |
| [Run Security Audit]({{ site.baseurl }}/guides/run-security-audit/) | Read-only security assessment with structured findings report |
| [Set Up a New Project]({{ site.baseurl }}/guides/setup-new-project/) | First session setup, indexing, and CLAUDE.md configuration |

---

## Requirements

Claude Code v1.0+ &bull; Node.js 18+ &bull; SQLite3 &bull; jq (recommended)
