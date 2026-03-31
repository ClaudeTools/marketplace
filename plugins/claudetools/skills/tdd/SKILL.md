---
name: tdd
description: >
  Test-driven development — write a failing test, make it pass, refactor. Use
  when implementing any feature or bug fix. No production code without a failing
  test first.
argument-hint: "[feature or component to implement]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [testing, tdd, implementation, quality]
---

# Test-Driven Development

> IRON LAW: No production code without a failing test first.

## The Cycle

```
RED → GREEN → REFACTOR → COMMIT
```

1. **RED:** Write a test that describes the behavior you want. Run it. It MUST fail. If it passes, your test is wrong — it's not testing new behavior.

2. **GREEN:** Write the MINIMUM code to make the test pass. Not the elegant code. Not the complete code. The minimum.

3. **REFACTOR:** Now that tests pass, clean up. Remove duplication, improve names, simplify. Run tests after every change — they must stay green.

4. **COMMIT:** One commit per RED-GREEN-REFACTOR cycle.

## Rules

- **Write the test FIRST.** Before the implementation file exists. Before the function is defined. The test comes first.
- **Run the test before implementing.** You must SEE it fail. "It would fail" is not the same as seeing the failure message.
- **Minimum code only.** In the GREEN step, write the least code possible. If you're adding features the test doesn't require, stop.
- **Tests must be specific.** `assert result is not None` tests nothing. `assert result == expected_value` tests behavior.
- **One behavior per test.** A test named `test_everything_works` is not a test.

## When to Use

Every time you write production code. The test comes first. Always.

## When NOT to Use

- Configuration files (no behavior to test)
- Documentation changes
- Purely visual/CSS changes (use screenshot comparison instead)
