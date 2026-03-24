---
title: "/code-review"
description: "Structured 4-pass code review command — correctness, security, performance, and maintainability. Read-only, no file modifications."
---

> **Status:** 🆕 New in v4.0 — migrated to native command format in the v4.0.0 release

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

## Quick example

```
/code-review src/api/payments.ts
```

**Claude responds:**

```
## Code Review: src/api/payments.ts

### Critical (must fix)
- payments.ts:84  — SQL query built with string concatenation; use parameterized queries
- payments.ts:127 — Stripe secret key read from process.env without validation; throws at runtime if unset

### Important (should fix)
- payments.ts:43  — refundPayment() catches Error but re-throws as a plain string; callers can't distinguish error types
- payments.ts:99  — no idempotency key on charge creation; duplicate charges possible if request retried

### Suggestions (nice to have)
- payments.ts:15  — extracting the retry logic into a shared helper would reduce duplication with subscriptions.ts

### Positive
- Consistent use of db transactions for charge + ledger updates
- Amount validation on entry (line 31) before any external calls
```

## Examples

```
/code-review
/code-review src/api/payments.ts
/code-review feature/add-webhooks
```

## Related

- [Review Code guide](/guides/review-code/) — walkthrough with real review output across three scenarios
- [Reference: code-reviewer agent](/reference/agents/code-reviewer/) — deeper review that cross-references the full codebase
- [Run a Security Audit guide](/guides/run-security-audit/) — full codebase security scan beyond a single diff
