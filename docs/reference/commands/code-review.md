---
title: /code-review
parent: Slash Commands
grand_parent: Reference
nav_order: 1
---

# /code-review

Structured 4-pass code review covering correctness, security, performance, and maintainability. Read-only — does not modify files.

## Invocation

```
/code-review [file-or-branch]
```

**Arguments:**
- `<file-path>` — review changes in a specific file
- `<branch-name>` — review diff against main
- *(empty)* — review uncommitted changes

## Workflow

1. Run `gather-diff.sh $ARGUMENTS` to collect the diff.
2. **Pass 1: Correctness** — logic, edge cases (null, empty, boundary), error paths, type correctness.
3. **Pass 2: Security** — SQL injection, XSS, secret exposure, path traversal, missing auth checks.
4. **Pass 3: Performance** — N+1 queries, missing indexes, unbounded loops, missing pagination.
5. **Pass 4: Maintainability** — follows existing patterns, naming consistency, duplication, test coverage.

## Output Format

```
## Code Review: {scope}

### Critical (must fix)
- [file:line] Description

### Important (should fix)
- [file:line] Description

### Suggestions (nice to have)
- [file:line] Description

### Positive
- What was done well
```

Categories with no findings are omitted. The Positive section is always included.

## Examples

```
/code-review
/code-review src/api/payments.ts
/code-review feature/add-webhooks
```
