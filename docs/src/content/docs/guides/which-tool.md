---
title: "Which Tool Should I Use?"
description: "Decision guide for choosing the right claudetools feature."
sidebar:
  order: 0
---

**Difficulty: Beginner**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
:::

Not sure whether to just ask Claude, use a slash command, or spawn an agent? This page maps common tasks to the right approach.

:::tip[The general rule]
Start with the simplest approach. Most tasks don't need a slash command or an agent — just ask Claude.

Reach for a slash command when you want a structured protocol enforced (evidence before fix, 4-pass review, intent before code).

Spawn an agent when the task is large enough to overflow your context window, or when you want it to run independently while you work on something else.
:::

---

## "I want to fix a bug"

**Simple bug** — just tell Claude what's wrong:

> "the login button is disabled after a failed auth attempt and never re-enables"

The investigating-bugs skill activates automatically. No command needed.

**Complex bug** — use the full protocol explicitly:

> "/investigating-bugs the payment webhook fails intermittently in production"

This forces the evidence-first workflow: Claude must produce a hypothesis with `file:line` evidence before suggesting any fix.

**Critical production incident** — spawn a dedicated agent:

> "spawn a bugfix-pipeline agent — users are getting logged out randomly, started after yesterday's deploy"

The pipeline agent runs root-cause analysis, cross-references recent commits, and produces a fix with a verification plan — without touching your main conversation context.

---

## "I want to build something"

**Small change (fewer than 3 files)** — just ask:

> "add a 'copy to clipboard' button to the code blocks on the docs page"

**Medium feature** — structure the work first:

> "/improving-prompts add email notifications when an invoice is overdue"

This refines your request into a well-scoped implementation brief before Claude starts coding.

**Large feature** — spawn the feature pipeline:

> "spawn a feature-pipeline agent to add a full CSV export workflow to the invoices page"

The pipeline creates tasks, decomposes them, runs implementation across parallel teammates, and does a code review pass — all without filling your context window.

**UI page or component** — trigger the design skill:

> "build a landing page for a legal document review SaaS"

The frontend-design skill runs intent questions and domain exploration before writing any code. See [Design a UI](design-a-ui.md).

---

## "I want to understand code"

**Quick question** — just ask:

> "what does `buildUserResponse` do and where is it called?"

The exploring-codebase skill activates automatically and answers in context.

**Deep dive** — invoke with a specific mode:

> "/exploring-codebase --mode dependency-graph src/api/auth.ts"

Modes: `map`, `dependency-graph`, `security-scan`, `dead-code`, `lint-summary`.

**Architecture review** — spawn a specialist:

> "spawn an architect agent to review the data layer and identify coupling issues"

The architect agent produces a structured report with specific file references, not general observations.

---

## "I want to review code"

**Informal** — just ask:

> "any issues with this function?"

Claude does a read-through and flags obvious problems. No severity ratings, no structured output.

**Structured pre-PR review** — use the skill:

> "/code-review"

Runs a 4-pass review (correctness, security, performance, maintainability) with severity-rated findings and `file:line` references. See [Review Code](review-code.md).

**Deep review** — spawn a specialist:

> "spawn a code-reviewer agent to review the entire auth module"

The agent cross-references the full codebase, not just the diff — it catches issues that require understanding how code is called from elsewhere.

---

## "I want to check security"

**Quick check** — just ask:

> "scan for security issues" or "check for hardcoded secrets"

Claude runs `security-scan.sh` automatically. Results in under 30 seconds.

**Full audit** — spawn the pipeline:

> "spawn a security-pipeline agent and run a full audit"

Four steps: full-audit, security-scan, dead security controls, dependency CVEs. Produces a structured report with recommended actions in priority order. See [Run a Security Audit](run-security-audit.md).

---

## "I want to manage work"

**Single task** — use TodoWrite directly:

> "remember to add rate limiting to the auth endpoint"

Tracked in the current session. Does not persist across sessions.

**Multi-task project** — use the task manager:

> "/managing-tasks new add CSV export to the invoices page"

Then decompose before starting: `/managing-tasks decompose task-a3f8b2c1`

This creates subtasks with dependencies that can execute in parallel.

**Multi-session project** — use restore and handoff:

- Start of session: `/managing-tasks restore`
- End of session: `/managing-tasks handoff`

The handoff writes `progress.md` with implementation detail so the next session has full context. See [Manage Tasks](manage-tasks.md).

---

## "I want multiple agents working"

**Parallel independent tasks** — use TeamCreate:

> "spawn three teammates: one to refactor the auth module, one to update the tests, one to update the docs"

Each teammate gets an isolated context window and works in parallel.

**Agents touching shared files** — add mesh coordination:

Check who's active before starting: `/mesh status`

Lock files before editing: `/mesh lock src/api/auth.ts 'mid-migration'`

**Long-running multi-session parallel work** — use worktrees:

```bash
git worktree add .claude/worktrees/my-feature -b my-feature
```

Each agent session runs in its own worktree with no git conflicts. The mesh coordinates at a higher level. See [Coordinate Agents](coordinate-agents.md).

---

## Quick reference

| Skill / Command | One-line description |
|-----------------|----------------------|
| `/build-a-feature` | Full implementation pipeline — plan, implement, review, commit |
| `/code-review` | 4-pass review: correctness, security, performance, maintainability |
| `/improving-prompts` | Turns rough requests into structured XML prompts |
| `/managing-tasks` | Create, track, and hand off tasks across sessions |
| `/claudetools:security-pipeline` | Full codebase security audit — read-only, findings only |
| `codebase-pilot` | Symbol search, file overview, import graph, dead code, change impact |
| `frontend-design` | Build production UI with design system, preview loop, contrast audit |
| `investigating-bugs` | Evidence-based root cause analysis for bugs |
| `agent-mesh` | File locks, message passing, and shared decisions across agents |
