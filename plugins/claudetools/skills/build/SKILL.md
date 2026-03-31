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

### Check project patterns

Before implementing, recall project-specific patterns from memory:
- Test framework and conventions (describe/it? test()? pytest fixtures?)
- Import patterns (relative? absolute? barrel files?)
- Error handling patterns (try/catch? Result type? error codes?)

```bash
cat $HOME/.claude/projects/*/memory/MEMORY.md 2>/dev/null | grep -iE "test|pattern|convention|style"
```

Follow existing patterns. Don't introduce new ones unless the plan explicitly calls for it.
If memory is empty or not relevant, detect patterns by reading existing test files.

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

6. **Report** (exact format):
   ```
   ✓ Task 3/7: [task name]
     Tests: 18/18 passing
     Files: src/middleware/auth.ts, tests/middleware/auth.test.ts
     Commit: a1b2c3d
   ```

### Step 4: Subagent dispatch (for independent tasks)

When the plan has independent tasks (no shared state, different files), dispatch fresh subagents.

#### Subagent dispatch pattern

For each independent task, use this exact invocation format:

```
Agent:
  subagent_type: "claudetools:implementing-features"
  mode: bypassPermissions
  prompt: |
    ## Task: [task name]

    **Context:** [project type], test command: [detected command]

    **Files:**
    - Create: [exact paths from plan]
    - Modify: [exact paths from plan]

    **Steps:**
    1. Write failing test: [test code from plan]
    2. Run: [test command] — verify FAIL
    3. Implement: [implementation code from plan]
    4. Run: [test command] — verify PASS
    5. Commit: git add [files] && git commit -m "[message]"

    Report status: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED.
  run_in_background: true
```

**Review after each subagent completes:**
1. Run test suite — still passing?
2. Check commit message — conventional format?
3. Any concerns flagged? Address before proceeding.

Do not dispatch the next subagent until the previous one's work is verified.

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

### Progress format

After all tasks complete, report in this exact format:

```
✓ All 7/7 tasks complete
  Tests: 42/42 passing (npm test, exit 0)
  No stubs (grep clean)
  Commits: 7 (a1b2c3d..f8e9d0a)

  Ready to ship? → /ship
```

Then ask:
```
AskUserQuestion:
  question: "All tasks complete. Ready to ship?"
  options:
    - label: "Ship it"
      description: "Run /ship to review, create PR, and deploy"
    - label: "Review first"
      description: "I want to check the code before shipping"
```

## Safety Net

If /build is followed correctly, these validators should never fire:
- `stubs.sh` — TDD eliminates stubs in the RED phase
- `ran-checks.sh` — tests run in every GREEN phase
- `blind-edit.sh` — plan maps all files; nothing is edited without context
- `no-deferred-actions.sh` — every task is completed, not deferred
