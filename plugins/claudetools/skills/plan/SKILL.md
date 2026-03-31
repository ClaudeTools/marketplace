---
name: plan
description: >
  Write a concrete implementation plan with bite-sized tasks, exact file paths,
  and complete code for each step. Use after brainstorming to create the roadmap
  for implementation.
argument-hint: "[feature name or design summary]"
allowed-tools: Read, Glob, Grep, Bash, Write, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [planning, implementation, tasks, TDD]
---

# Write Implementation Plan

> Create a plan that an engineer with zero context could execute perfectly.

## Plan Structure

Save plans to `docs/plans/YYYY-MM-DD-<feature-name>.md`.

Every plan starts with:
```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]
```

## Task Format

Each task is one self-contained change:

```markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file`
- Modify: `exact/path/to/existing`

Steps:
- [ ] Write the failing test (show the test code)
- [ ] Run test, verify it fails
- [ ] Write minimal implementation (show the code)
- [ ] Run test, verify it passes
- [ ] Commit
```

## Rules

1. **Exact file paths** — always
2. **Complete code** in every step — if a step changes code, show the code
3. **No placeholders** — never write "TBD", "add appropriate handling", or "similar to Task N"
4. **Bite-sized steps** — each step is one action (2-5 minutes)
5. **Test first** — every task starts with a failing test where applicable
6. **Frequent commits** — one commit per task

## After Writing

Tell the user: "Plan complete. **Next: /build** to execute it task by task."
