---
name: workflow
description: >
  Orchestrates the full senior engineer workflow — maps tasks to phases, enforces
  phase ordering, and routes to the right skill at each step. Use at the start of
  any non-trivial task to ensure no phase is skipped.
argument-hint: "[task description or 'status' to see current phase]"
allowed-tools: Glob, Grep, Read, Bash, AskUserQuestion, TaskCreate, TaskUpdate
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [workflow, orchestration, process, phases]
---

# Engineering Workflow Conductor

> Every non-trivial task follows a workflow. This skill maps your task to the right
> phases and ensures you don't skip steps. It doesn't do the work — it tells you
> which skill should do the work at each phase.

## Task Classification

First, classify the task:

| Task Type | Workflow |
|-----------|---------|
| **New feature** | /research → /design → /build → /review → /ship |
| **Bug fix** | /debug → /build → /review → /ship |
| **Refactor** | /explore → /design → /build → /review → /ship |
| **Research/exploration** | /explore → /research |
| **Maintenance** | /health → /improve |
| **Documentation** | /explore → docs |

## Phase Definitions

### 1. RESEARCH — Understand before you act
**Skill:** `/research` (claudetools)
**When complete:** External dependencies identified, docs read, assumptions verified.
**Skip if:** Task is purely internal with no external dependencies.

### 2. EXPLORE — Learn the codebase
**Skill:** `/explore` (claudetools:codebase-explorer)
**When complete:** Relevant files found, architecture understood, patterns identified.
**Skip if:** You're already deeply familiar with this area of the code.

### 3. DESIGN — Think before you build
**Skill:** Use `superpowers:brainstorming` then `superpowers:writing-plans`
**When complete:** Design approved by user, implementation plan written and saved.
**Skip if:** Task is a simple, well-defined bug fix with obvious solution.

### 4. BUILD — Implement with discipline
**Skill:** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`
**When complete:** All plan tasks done, tests passing, code committed.
**NEVER skip.**

### 5. DEBUG — Investigate before you fix
**Skill:** `/debug` (claudetools:debugger)
**When complete:** Root cause identified with evidence.
**Only for:** Bug fix workflow.

### 6. REVIEW — Verify before you ship
**Skill:** `/review` (claudetools:code-review)
**When complete:** 4-pass review done, all issues addressed.
**NEVER skip** for changes that will be merged.

### 7. SHIP — Deliver with confidence
**Skill:** Use `superpowers:finishing-a-development-branch`
**When complete:** Branch merged or PR created, docs updated.
**NEVER skip.**

### 8. HEALTH — Monitor and improve
**Skill:** `/health` (claudetools:session-dashboard + field-review)
**When complete:** Health report generated, issues identified.
**Use for:** Maintenance workflow only.

## Enforcement

At each phase transition, verify the previous phase is complete:

- **Before DESIGN:** Have you researched external dependencies? (If applicable)
- **Before BUILD:** Is there an approved design and written plan?
- **Before REVIEW:** Are all tests passing? Is all code committed?
- **Before SHIP:** Has the code been reviewed?

If a phase was skipped, go back. Skipping phases is how quality drops.

## Handoff Pattern

Every phase ends by telling you what comes next:

"Research complete. External dependencies verified. **Next: /design** to brainstorm approaches."

"Design approved. Plan saved. **Next: /build** to implement the plan."

"Implementation complete. All tests passing. **Next: /review** for code quality check."

"Review passed. No issues. **Next: /ship** to merge and deliver."
