---
title: "Which Tool Should I Use?"
description: "Decision guide — pick the right claudetools skill for your task."
sidebar:
  order: 0
---

Not sure which command or skill to reach for? Use this page to find the right tool quickly.

## By what you want to do

### I want to build something new

| What | Use |
|------|-----|
| A full feature (API + UI + tests) | [`/build-a-feature`](build-a-feature.md) |
| A UI page or component | Ask "design a [thing]" → [`designing-interfaces`](design-a-ui.md) |
| Something with a vague spec | [`/improving-prompts`](improve-prompts.md) — structure it first |
| A backlog item to do later | [`/improving-prompts task`](improve-prompts.md) — converts to tracked tasks |

### I want to understand existing code

| What | Use |
|------|-----|
| Overview of an unfamiliar project | Ask "map this codebase" → [`codebase-pilot map`](explore-a-codebase.md) |
| How a specific function works | Ask "what does X do?" → [`find-symbol`](explore-a-codebase.md) |
| How a request flows end-to-end | Ask "how does /api/X work?" → [`find-route`](explore-a-codebase.md) |
| What imports a file or function | Ask "what uses X?" → [`find-usages`](explore-a-codebase.md) |
| Blast radius before a refactor | Ask "what breaks if I change X?" → [`change-impact`](explore-a-codebase.md) |
| Unused code to clean up | Ask "any dead code?" → [`dead-code`](explore-a-codebase.md) |

### I want to check for problems

| What | Use |
|------|-----|
| Review a PR branch before merging | `/code-review feature/branch-name` → [Review Code](review-code.md) |
| Review a file before touching it | `/code-review src/path/to/file.ts` → [Review Code](review-code.md) |
| Review my uncommitted changes | `/code-review` (no argument) → [Review Code](review-code.md) |
| Full codebase security audit | `/claudetools:security-pipeline` → [Run a Security Audit](run-security-audit.md) |
| Quick secrets/injection scan | Ask "scan for security issues" → [Run a Security Audit](run-security-audit.md) |
| Debug a specific bug | `/debug-a-bug` or ask "why is X happening" → [Debug a Bug](debug-a-bug.md) |

### I want to manage work

| What | Use |
|------|-----|
| Track a task across sessions | `/managing-tasks new` → [Manage Tasks](manage-tasks.md) |
| Break a big task into subtasks | `/managing-tasks decompose` → [Manage Tasks](manage-tasks.md) |
| Hand off work to the next session | `/managing-tasks handoff` → [Manage Tasks](manage-tasks.md) |
| Resume from a previous session | `/managing-tasks restore` → [Manage Tasks](manage-tasks.md) |
| Run work in parallel with teammates | `TeamCreate` → [Coordinate Agents](coordinate-agents.md) |
| Avoid conflicts on shared files | `agent-mesh lock` → [Coordinate Agents](coordinate-agents.md) |

---

## By how you want to work

:::tip[Just tell Claude what you want]
For most tasks you do not need to know a command. Just describe what you want in plain English — claudetools hooks will detect the intent and activate the right skill. The commands and skills listed here are for when you want to be explicit.
:::

**"I have a clear task, just do it"**
→ Just say it. Or use `/build-a-feature` for structured implementation with verification.

**"I have a vague idea and want Claude to structure it before acting"**
→ Use `/improving-prompts` (execute mode) — it structures the request and runs immediately.

**"I want to see the plan before Claude touches anything"**
→ Use `/improving-prompts plan` — shows the full structured prompt for your approval first.

**"I want to work on this across multiple sessions"**
→ Use `/improving-prompts task` or `/managing-tasks new` — both create persistent tracked tasks.

**"I want multiple agents working in parallel"**
→ Use `TeamCreate` directly, or ask Claude to spawn teammates. Use the agent mesh if they share files.

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
| `designing-interfaces` | Build production UI with design system, preview loop, contrast audit |
| `debugging-pipeline` | Evidence-based root cause analysis for bugs |
| `agent-mesh` | File locks, message passing, and shared decisions across agents |

---

## Still not sure?

Ask Claude: "what's the best way to [describe your goal]?" — it will recommend the right skill and explain why.
