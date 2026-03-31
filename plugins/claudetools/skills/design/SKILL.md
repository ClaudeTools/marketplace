---
name: design
description: >
  Full design phase — discover the problem, research dependencies, architect a
  solution, and write the implementation plan. Use before building anything
  non-trivial. This is the first command in the /design → /build → /ship workflow.
argument-hint: "[what to build or change]"
allowed-tools: Read, Glob, Grep, Bash, WebSearch, WebFetch, Write, AskUserQuestion, Agent
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [design, discovery, architecture, planning, workflow]
---

# /design — Discover, Architect, Plan

> HARD GATE: Do NOT write implementation code until the user has approved the design
> AND the plan is written. This applies to EVERY task regardless of perceived simplicity.

## Why This Gate Exists

| Rationalization | Reality |
|----------------|---------|
| "This is too simple to need a design" | Simple tasks with unexamined assumptions cause the most wasted work |
| "I already know how to do this" | You know how to do it in your training data. This codebase may differ. |
| "Let me just start coding and refactor later" | Refactoring code you shouldn't have written costs 3x more than designing first |
| "The user seems impatient" | A 2-minute design conversation saves 20 minutes of wrong-direction work |

## The Process

### Phase 1: Discover

Understand the problem before solving it.

1. **Explore the codebase** using codebase-pilot:
   ```bash
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<relevant-name>"
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<entry-point>"
   ```

2. **Check memory** for past decisions about this area:
   - Read `$HOME/.claude/projects/*/memory/MEMORY.md` for relevant entries
   - "Last time you worked on auth, you chose JWT because..."

3. **Research external dependencies** (if task touches external APIs/libraries):
   - Use WebSearch + WebFetch to find current documentation
   - Verify API endpoints, SDK versions, auth methods
   - Skip if task is purely internal

4. **Ask clarifying questions** — one at a time via AskUserQuestion:
   - What problem does this solve? (if not obvious)
   - What constraints exist? (performance, compatibility, etc.)
   - What does success look like?

### Phase 2: Architect

Present 2-3 approaches with tradeoffs.

Use AskUserQuestion with preview panels to show each approach:

```
AskUserQuestion:
  question: "Which approach for [feature]?"
  options:
    - label: "Approach A: [name]"
      description: "[1-sentence tradeoff]"
      preview: |
        Architecture:
        [component diagram or code structure]

        Pros: [key advantage]
        Cons: [key disadvantage]
        Files: [N files changed]
    - label: "Approach B: [name]"
      ...
```

Lead with your recommendation. Explain why in 1 sentence.

### Phase 3: Plan

After the user approves an approach, write the implementation plan:

1. **Map files** — use `related-files` and `file-overview` to list every file to create/modify
2. **Write tasks** — each task is one self-contained change:
   - Exact file paths
   - Complete code in every step
   - Test-first: failing test → implementation → verify → commit
   - No placeholders (never write "TBD", "add appropriate handling", "similar to Task N")
3. **Self-review** — check for: spec coverage, placeholder scan, type consistency
4. **Save** to `docs/plans/YYYY-MM-DD-<name>.md`

### Phase 4: Handoff

Present the plan summary and ask:

```
AskUserQuestion:
  question: "Plan ready — N tasks, M files. Start building?"
  options:
    - label: "Build it"
      description: "Execute the plan task-by-task with TDD"
    - label: "Review plan first"
      description: "Show the full plan for review before building"
    - label: "Adjust"
      description: "I want to change something in the design"
```

If "Build it" → tell the user: "Starting build phase. **Next: /build**"

## Safety Net

If /design is followed correctly, these validators should never fire:
- `task-scope.sh` — scope is defined by the plan's acceptance criteria
- `unasked-deps.sh` — dependencies are identified in the discovery phase
- `unasked-restructure.sh` — structural changes are in the plan
- `research-backing.sh` — external APIs were researched in discovery
