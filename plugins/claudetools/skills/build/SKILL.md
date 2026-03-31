---
name: build
description: >
  Execute an implementation plan with test-driven development. Dispatches fresh
  subagents per task, runs TDD (test first, implement, verify), and tracks progress.
  Second command in the /design → /build → /ship workflow.
argument-hint: "[plan-file-path or 'continue']"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TaskCreate, TaskUpdate
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [build, development, TDD, implementation, workflow]
---

# /build — Develop, Test, Verify

> IRON LAW: No production code without a failing test first. Every task follows
> RED → GREEN → REFACTOR → COMMIT.

## Prerequisites

A plan must exist. If no plan file is provided and none found in `docs/plans/`:
```
"No plan found. Run /design first to create one."
```

## Why Test-First

| Excuse | Reality |
|--------|---------|
| "I'll write tests after" | Tests-after answer "what does this code do?" Tests-first answer "what SHOULD this code do?" — fundamentally different |
| "TDD slows me down" | TDD is faster than debugging. Time spent writing a test: 2 min. Time spent debugging without one: 20 min. |
| "This is too simple to test" | Simple code with tests stays simple. Simple code without tests becomes complex when the next person changes it. |
| "I'll just run it and see" | Manual verification is not repeatable. Automated tests are. |

## The Process

### Step 1: Load the plan

Read the plan file. Extract all tasks with full text.

### Step 2: Detect project test framework

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/lib/detect-project.sh
PROJECT_TYPE=$(detect_project_type)
```

| Project Type | Test Command | Test File Pattern |
|-------------|-------------|-------------------|
| node | `npm test` or `npx vitest` or `npx jest` | `*.test.ts`, `*.spec.ts` |
| python | `pytest` or `python -m unittest` | `test_*.py`, `*_test.py` |
| rust | `cargo test` | `#[cfg(test)]` modules |
| go | `go test ./...` | `*_test.go` |
| shell | `bats tests/` | `*.bats` |

### Step 3: Execute tasks

For each task in the plan:

1. **Show progress:**
   ```
   "Task 3/7: [task name]"
   ```

2. **RED — Write the failing test:**
   - Create the test file with the test code from the plan
   - Run the test command
   - Confirm it FAILS (if it passes, the test is wrong)

3. **GREEN — Write minimal implementation:**
   - Write the minimum code to make the test pass
   - Run the test command
   - Confirm it PASSES

4. **REFACTOR — Clean up:**
   - Remove duplication, improve names, simplify
   - Run tests again — must still pass

5. **COMMIT:**
   ```bash
   git add <specific files>
   git commit -m "feat: [task description]"
   ```

6. **Report:**
   ```
   "✓ Task 3/7 complete. Tests: 12/12 passing."
   ```

### Step 4: Subagent dispatch (for independent tasks)

When the plan has independent tasks (no shared state, different files), dispatch fresh subagents:

```
Agent:
  prompt: "[full task text from plan + project context + TDD instructions]"
  mode: bypassPermissions
  run_in_background: true
```

Each subagent gets:
- The complete task text (not a reference to the plan file)
- Project type and test command
- TDD instructions: "Write failing test first. Run it. Then implement."
- The commit message format

After each subagent completes, verify its work:
- Run the test suite
- Check the commit message
- If issues found, dispatch a fix agent

### Step 5: Final verification

After all tasks complete:

```bash
# Run full test suite
[test command for project type]

# Check for stubs
grep -rn 'TODO\|FIXME\|NotImplementedError\|throw.*not implemented' [source files]

# Verify all plan tasks are committed
git log --oneline -[N]
```

Report:
```
"✓ All 7/7 tasks complete. Tests: 34/34 passing. No stubs. Ready for review."
AskUserQuestion: "Ready to ship?" → /ship
```

## Safety Net

If /build is followed correctly, these validators should never fire:
- `stubs.sh` — TDD eliminates stubs in the RED phase
- `ran-checks.sh` — tests run in every GREEN phase
- `blind-edit.sh` — plan maps all files; nothing is edited without context
- `no-deferred-actions.sh` — every task is completed, not deferred
