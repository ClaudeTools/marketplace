---
title: "Tutorial: Safe Refactor"
description: "Rename a function across a codebase safely — see change-impact analysis, hooks catching incomplete edits, and code review before you commit."
sidebar:
  order: 3
---

**Goal:** Rename a function that's used in many places, using claudetools safety nets to ensure nothing breaks and every caller is updated.

**Prerequisites:**
- claudetools installed — see [Installation](/getting-started/installation/)
- Familiar with hooks and codebase-pilot — see [Core Concepts](/getting-started/core-concepts/)

**Time estimate:** ~15 minutes

---

## The scenario

You have a function called `getUser` in `src/services/user-service.ts`. It does more than fetch — it also validates and enriches — so you want to rename it to `resolveUser` across the codebase. It's used in 6 places. You want to be sure every caller gets updated and nothing is accidentally left behind.

---

## Step 1 — State the refactor goal

> **You:** "I want to rename `getUser` to `resolveUser` in `src/services/user-service.ts`. It's exported and probably used in several places. Make sure everything is updated safely."

Claude doesn't start editing immediately. It analyses first.

:::note[What just happened: refactor-pipeline activates]
The [refactor pipeline](/reference/agents/refactor-pipeline/) activates for multi-file changes. It runs: impact analysis → decompose → implement → verify. No edits happen until the impact is understood.
:::

---

## Step 2 — Change impact analysis

> **Claude:** "Before any edits, I'll run change-impact analysis on `getUser`...
>
> ```
> codebase-pilot change-impact "getUser"
>
> Direct callers (6 files):
>   src/routes/users.ts:28         getUser(req.params.id)
>   src/routes/auth.ts:41          getUser(decoded.userId)
>   src/worker.ts:55               getUser(job.data.userId)
>   src/middleware/auth.ts:19      getUser(tokenPayload.sub)
>   tests/routes/users.test.ts:34  getUser mock
>   tests/services/user.test.ts:12 getUser direct call
>
> Re-exports: none
> Type references: 0 (not used in type positions)
> ```
>
> 6 callers across routes, middleware, a worker, and 2 test files. No re-exports to worry about. I'll update all of them."

:::note[Why this matters]
Without [codebase-pilot](/getting-started/core-concepts/#codebase-pilot), you'd rely on text search — which misses dynamic calls, aliases, and re-exports. Change-impact traces the actual import and call graph.
:::

---

## Step 3 — The edits begin

Claude works through the files one by one. It reads each file before editing:

> **Claude:** "Reading `src/services/user-service.ts`... Renaming function declaration and export."

> **Claude:** "Reading `src/routes/users.ts`... Updating import and call at line 28."

> **Claude:** "Reading `src/routes/auth.ts`... Updating import and call at line 41."

After three files, Claude tries to edit `src/worker.ts` — but it skips straight to editing without reading it first.

:::caution[Hook fires: read-before-edit blocked]
```
[PreToolUse] read-before-edit: cannot edit src/worker.ts
— file has not been read in this session.
Read the file before editing it.
```
Claude is stopped. It reads `src/worker.ts`, then continues the edit.
:::

This is the [read-before-edit hook](/reference/hooks/process-hooks/) in action. It prevents edits based on stale assumptions — Claude must see the current state of a file before changing it.

---

## Step 4 — Stub detection

After updating `src/middleware/auth.ts`, Claude begins updating the test files. It writes a quick placeholder for the mock:

```typescript
// tests/routes/users.test.ts
jest.mock('../services/user-service', () => ({
  resolveUser: jest.fn(), // TODO: add implementation
}));
```

:::caution[Hook fires: stub detected]
```
[PostToolUse] no-stubs: placeholder comment detected in
tests/routes/users.test.ts — "TODO: add implementation"
Complete the implementation before continuing.
```
:::

The [no-stubs hook](/reference/hooks/quality-hooks/) fires on the `// TODO` comment. Claude fills in the real mock before moving on:

```typescript
jest.mock('../services/user-service', () => ({
  resolveUser: jest.fn().mockResolvedValue({
    id: 'user-1',
    email: 'alice@example.com',
    role: 'user',
  }),
}));
```

---

## Step 5 — Code review before commit

All 6 callers are updated. Before committing, you want a second pass:

> **You:** "Review the refactor before I commit."

The [code-review skill](/reference/commands/code-review/) runs a 4-pass structured review:

> **Claude (pass 1 — correctness):** "All 6 `getUser` references replaced with `resolveUser`. No remaining `getUser` calls in the codebase. Function signature unchanged — callers don't need updating beyond the name."

> **Claude (pass 2 — safety):** "No new secrets introduced. The rename is mechanical — no logic change. The mock in `users.test.ts` now returns a complete user object rather than a partial."

> **Claude (pass 3 — type integrity):** "Running typecheck..."
>
> ```bash
> npx tsc --noEmit
> # ✓ No errors
> ```

> **Claude (pass 4 — test coverage):** "The direct call in `tests/services/user.test.ts:12` was updated. Coverage unchanged — the test exercises the same logic under the new name."

> **Summary:** "4-pass review complete. The rename is clean. Recommend committing with: `refactor: rename getUser → resolveUser in user-service`"

---

## Step 6 — Commit

> **You:** "Commit it."

:::note[Hook fires: commit message validated]
The commit message `refactor: rename getUser → resolveUser in user-service` is checked by the commit-hygiene [hook](/getting-started/core-concepts/#hook). It passes — it's a valid conventional commit with a `refactor:` prefix, a clear description, and no fixup markers.
:::

```bash
git commit -m "refactor: rename getUser → resolveUser in user-service"
# [main a4f91c2] refactor: rename getUser → resolveUser in user-service
# 6 files changed, 12 insertions(+), 12 deletions(-)
```

---

## What you learned

| Feature | What it did |
|---------|------------|
| `codebase-pilot change-impact` | Found all 6 callers before any edit |
| [read-before-edit hook](/reference/hooks/process-hooks/) | Stopped an edit on an unread file |
| [no-stubs hook](/reference/hooks/quality-hooks/) | Caught a `// TODO` placeholder in test mock |
| [code-review skill](/reference/commands/code-review/) | Ran 4-pass review before commit |
| commit-hygiene hook | Validated conventional commit format |

The whole rename touched 6 files, caught 2 hook violations before they became problems, and shipped with a clean review.

---

## Things that would have gone wrong without claudetools

- **Missed caller:** Text search for `getUser` would miss aliased imports like `import { getUser as fetchUser }`
- **Stale edit:** Without read-before-edit, Claude could have overwritten a file that was modified since the session started
- **Incomplete mock:** The `// TODO` stub would have silently passed tests that assert the mock was called, with wrong return data
- **Non-conventional commit:** A message like `"renamed function"` would have failed the commit hook and required a retry

---

## Next steps

- [Tutorial: Your First Bug Fix](tutorial-first-bug-fix.md) — apply the same read-first discipline to debugging
- [Build a Feature](build-a-feature.md) — larger multi-file changes with the full feature pipeline
- [Reference: Refactor Pipeline](/reference/agents/refactor-pipeline/)
- [Reference: Process Hooks](/reference/hooks/process-hooks/)
