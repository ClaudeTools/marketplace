---
title: "Test Writer"
description: "Test generation agent — matches existing project patterns and frameworks, focusing on edge cases, error paths, and boundary values."
---

> **Status:** ✅ Stable — included in all claudetools versions

Generate tests following existing project patterns. Invoked when test coverage is needed for new or changed code.

## Purpose

Reads existing test files to match the project's testing style, framework, and conventions before writing anything. Generates tests that focus on edge cases, error paths, and boundary values — not trivial assertions that only verify a function exists. Runs the tests to verify they pass.

## Model

`sonnet`

## Tool Access

Full access: `Glob, Grep, LS, Read, Edit, Write, NotebookRead, Bash, WebFetch, WebSearch, TodoWrite, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, KillShell, BashOutput`

## Workflow

1. Detects the test framework from `package.json`, `Cargo.toml`, or equivalent
2. Reads existing test files for the affected module or nearby code to match style and conventions
3. Understands the code under test (reads implementation, not just types)
4. Writes tests targeting:
   - Happy path behaviour
   - Edge cases (empty inputs, boundary values, overflow)
   - Error paths (invalid inputs, missing dependencies, network failures)
   - The specific behaviour described in the task
5. Runs the tests to verify they pass
6. Fixes any test setup issues discovered during the run

## When to Use

- A new feature was implemented and needs test coverage
- A bug was fixed and a regression test is needed
- Code coverage is being improved on an existing module
- As the final step in a pipeline before committing

## Example Usage

```
Use the test-writer agent to add tests for the new invoice pagination logic in src/routes/invoices.ts.
```

The agent reads the existing invoice test file, understands the pagination implementation, and writes tests covering: the default page size, explicit page and limit parameters, the last page with fewer results than the limit, and invalid page values returning a 400 error.

## Related

- [Build a Feature guide](/guides/build-a-feature/) — test-writer is the final step in the feature pipeline
- [Reference: code-reviewer agent](code-reviewer.md) — code review often precedes test writing in the pipeline
- [Reference: bugfix-pipeline agent](bugfix-pipeline.md) — adds a regression test as part of the fix confirmation step
