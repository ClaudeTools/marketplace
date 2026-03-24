---
title: "Review Code"
description: "Run a structured 4-pass code review on a branch, a file, or uncommitted changes — correctness, security, performance, maintainability."
---

**Difficulty: Intermediate**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- A git repository with code changes to review (a branch, file, or uncommitted diff)
:::


Use `/code-review` to run a structured 4-pass review — correctness, security, performance, maintainability — on a branch, a file, or your uncommitted changes.

## Real scenarios

### Scenario A: Review a PR branch

> "review the changes on feature/add-auth"

Claude detects `feature/add-auth` as a branch name and diffs it against `main`:

:::note[Behind the scenes]
`gather-diff.sh feature/add-auth` runs `git diff main...feature/add-auth` and groups changes by file. The 4-pass review runs on that diff only — not the full codebase.
:::

```
## Code Review: feature/add-auth

### Critical (must fix)
- [src/api/users.ts:87] Missing null check — `user.profile` accessed directly after
  `getUserById()` which can return null when the user does not exist. Will throw
  at runtime on any unauthenticated request that reaches this path.

- [src/db/query-builder.ts:34] SQL injection — `filterClause` is built from raw
  string interpolation of `req.query.search`. Replace with parameterised query:
  `WHERE name ILIKE $1` with `['%' + term + '%']` as the bound value.

### Important (should fix)
- [src/api/users.ts:112–138] N+1 query — `getUserPermissions(userId)` is called
  inside a `.map()` over the results of `listUsers()`. For 100 users this fires
  101 queries. Batch with a single `WHERE user_id = ANY($1)` call instead.

### Suggestions (nice to have)
- [src/api/users.ts:52] `buildUserResponse()` and `formatUserPayload()` share
  identical field-mapping logic. Extract to a single `toUserDTO(user)` helper.

### Positive
- Auth middleware correctly placed before all protected routes
- TypeScript strict mode maintained throughout — no implicit `any`
- JWT expiry and refresh logic is clean and well-scoped
```

---

### Scenario B: Review a specific file

> "/code-review src/api/users.ts"

Claude focuses the 4 passes on that single file:

:::note[Behind the scenes]
`gather-diff.sh src/api/users.ts` reads the full file content. All findings reference `src/api/users.ts:line`.
:::

```
## Code Review: src/api/users.ts

### Critical (must fix)
- [src/api/users.ts:87] Unhandled null — see above

### Important (should fix)
- [src/api/users.ts:203] Missing rate limiting on /api/users/login — brute force
  is possible. Add the existing `rateLimiter` middleware used on /api/auth/token.

### Suggestions (nice to have)
- [src/api/users.ts:14] `MAX_PAGE_SIZE = 500` is defined locally here and also
  in src/config/pagination.ts — use the shared constant.

### Positive
- Input validation on all POST/PATCH handlers using the shared schema validators
- Consistent error response shape throughout
```

---

### Scenario C: Review before committing

> "review my uncommitted changes"

:::note[Behind the scenes]
`gather-diff.sh` with no argument runs `git diff HEAD` (staged + unstaged). If nothing is staged, it also checks `git status` for untracked new files.
:::

```
## Code Review: uncommitted changes (3 files)

### Important (should fix)
- [src/hooks/useAuth.ts:41] `localStorage.setItem('token', rawToken)` — storing
  the raw JWT in localStorage exposes it to XSS. Use an httpOnly cookie or
  keep in memory only.

### Suggestions
- [src/components/UserMenu.tsx:28] `isAdmin` prop is passed but never read in
  this component — remove or use it.

### Positive
- All new components have corresponding test files
- No hardcoded strings — copy routed through i18n keys
```

---

:::tip[When to use what]
- **Quick scan**: Ask "any issues with this file?" — Claude does an informal read-through without the structured 4-pass protocol
- **Structured review**: Use `/code-review` for severity-rated findings with `file:line` references — good for pre-PR checks
- **Deep review**: Say "spawn a code-reviewer agent" for thorough analysis that cross-references the full codebase, not just the diff
:::

## What happens behind the scenes

- The review is **read-only** — no files are modified
- All findings include `file:line` so you can jump directly to the issue
- The 4-pass structure means security and performance are never skipped, even on small diffs
- The **Positive** section is intentional — reinforce patterns you want the team to repeat
- Categories with no findings are omitted from the output

## Tips

- Run `/code-review` before every PR — catching issues locally is faster than in review
- For a branch review, the diff is against `main` — rebase first if main has advanced significantly
- To focus on one pass on a large diff, say "focus on security only" after the review starts
- Combine with the feature pipeline: [`build-a-feature`](build-a-feature.md) runs code-review automatically after implementation

## Related

- [Build a Feature](build-a-feature.md) — the feature pipeline runs code-review automatically after implementation
- [Run a Security Audit](run-security-audit.md) — full codebase security scan, not just changed files
- [Reference: /code-review command](../reference/commands/code-review.md)
