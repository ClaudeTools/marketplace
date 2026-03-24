---
title: "Debug a Bug"
description: "Walk through a real bug investigation — REPRODUCE through CONFIRM with actual prompts and output."
---

**Difficulty: Intermediate**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- [Core Concepts](../getting-started/core-concepts.md) — understanding hooks and the debugger skill
- [Explore a Codebase](explore-a-codebase.md) — the OBSERVE step relies on codebase-pilot navigation
:::


A full walkthrough of the debugger protocol using a realistic example. See the prompts, the output, and where things go wrong the first time.

:::tip[When to use what]
- **Simple bug** (error message, obvious location): Just tell Claude — debugger activates automatically from keywords like "broken", "failing", "why is", "error"
- **Complex multi-file bug**: Use `/debugger` explicitly to invoke the full structured protocol
- **Critical production bug**: Spawn the `bugfix-pipeline` agent for a coordinated fix + review + verification cycle
:::

---

## The bug

> **You:** "The API returns 500 when updating a user's email. It started after yesterday's deploy."

:::note[Hook fires: debugger skill activates]
"500" and "started after" are enough. The skill takes over — the 6-step protocol runs in sequence and cannot skip ahead.
:::

---

## Step 1 — REPRODUCE

Claude reads the route handler and tries to reconstruct the failure path:

> "REPRODUCE: Reading `api/src/routes/users.ts`... Found `PATCH /users/:id`. It validates the request body with Zod, then calls `UserService.updateEmail`. Let me check what error the service throws."
>
> "I can't run the request directly, but I can trace the code path. Reading `api/src/services/user-service.ts`..."

```bash
# Claude checks git history to surface what changed yesterday
git log --oneline --since="1 day ago" -- src/services/user-service.ts
# a3f92c1 feat: add email uniqueness check
```

> "Found it — a uniqueness check was added yesterday. Let me read that commit."

---

## Step 2 — OBSERVE

> "OBSERVE: The new uniqueness check in `user-service.ts:34` runs `SELECT COUNT(*) WHERE email = ?`. If the email already belongs to the user making the request, the count is 1 (their own record) and the check throws `EmailAlreadyInUse`. So updating to the same email you already have causes a 500."

Claude reads the related test file:

> "The test in `tests/user-service.test.ts:88` only tests updating to a *new* email. There's no test for updating to your existing email — which is a valid no-op that should succeed."

---

## Step 3 — HYPOTHESIZE

> "HYPOTHESIZE: The uniqueness check doesn't exclude the current user's own email. When a user updates their profile (submitting the form with their existing email unchanged), the check finds their own record, counts it as a collision, and throws. Root cause: `WHERE email = ?` should be `WHERE email = ? AND id != ?`."

This is a specific, testable claim with evidence: the line number, the SQL, and the scenario that triggers it.

---

## Step 4 — VERIFY

> "VERIFY: Confirming the query in `user-service.ts:34`..."

```typescript
// Current (broken)
const count = await db.query(
  'SELECT COUNT(*) FROM users WHERE email = $1',
  [newEmail]
);

// The fix: exclude the user being updated
const count = await db.query(
  'SELECT COUNT(*) FROM users WHERE email = $1 AND id != $2',
  [newEmail, userId]
);
```

> "Confirmed — the current query counts the user's own record. Any update that keeps the same email will trigger the uniqueness error. Hypothesis verified."

---

## Step 5 — FIX

> "FIX: Updating `user-service.ts:34` to exclude the current user from the uniqueness check. Also adding a test for the same-email-update case."

**`api/src/services/user-service.ts:34`** — adds `AND id != $2` to the query.

**`tests/user-service.test.ts`** — adds:
```typescript
it('allows updating to the same email (no-op)', async () => {
  const user = await createUser({ email: 'alice@example.com' });
  await expect(UserService.updateEmail(user.id, 'alice@example.com')).resolves.not.toThrow();
});
```

---

## Step 6 — CONFIRM

```bash
npx tsc --noEmit          # passes
npm test -- --grep "email" # 4 tests pass, 0 fail
```

> "CONFIRM: Typecheck passes. All email-related tests pass including the new same-email test. The 500 on update is resolved."

---

## When the first hypothesis is wrong

Sometimes the HYPOTHESIZE step gets it wrong. Here's what that looks like:

> **You:** "Users are getting logged out randomly — maybe every 10-15 minutes. Not all of them, just some."

**First hypothesis:**

> "HYPOTHESIZE: The JWT expiry (`SESSION_TTL`) may be shorter than the refresh interval. If `SESSION_TTL=600` and the refresh runs every 900 seconds, some users miss the refresh window."

**VERIFY:**

> "Checking `SESSION_TTL` in `.env` — it's `86400` (24 hours). Checking the refresh interval... it's 300 seconds. The window is fine. Hypothesis is wrong."

:::caution[Two-strike rule]
After a failed hypothesis, Claude doesn't just try the next idea. It returns to OBSERVE with the failed hypothesis in view and asks: "what does this failure tell me about what I missed?" One more failed hypothesis and Claude adds diagnostic logging and restarts from scratch.
:::

**Back to OBSERVE:**

> "The logouts are intermittent and affect some users, not all. Let me look at what's different between affected and unaffected sessions... Checking `auth.ts` for anything user-specific."
>
> "Found it — the cookie `SameSite` attribute is `Strict`. Users accessing from a third-party redirect (password manager, email link) have their cookie dropped by the browser. It's not expiry — it's the cookie policy."

**Second hypothesis, correct:**

> "HYPOTHESIZE: `SameSite=Strict` drops the auth cookie on cross-site navigations. Users arriving from an email link or external redirect are treated as unauthenticated. Fix: change to `SameSite=Lax`."

The two-strike rule exists to prevent momentum from carrying Claude past a wrong turn. See [Core Concepts](../getting-started/core-concepts.md) for more on the protocol constraints.

---

## Related

- [Exploring a Codebase](explore-a-codebase.md) — map the code before diving into a bug
- [Run a Security Audit](run-security-audit.md) — find security-class bugs proactively
- [Reference: debugger skill](../../reference/skills/debugger.md)
