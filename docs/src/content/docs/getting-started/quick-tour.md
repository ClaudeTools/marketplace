---
title: "Quick Tour"
description: "Your first five minutes with claudetools — real prompts, real responses, real hooks."
---

A narrated walkthrough of your first five minutes. Every prompt is something you'd actually type. Every response is what you'd actually see.

---

## Minute 1: Install and open a session

```
/plugin install claudetools@claudetools-marketplace
```

Open a new Claude Code session. You won't see a splash screen — claudetools is silent when everything works. Behind the scenes:

:::note[What just happened]
- 51 hooks registered across 17 lifecycle events
- Memory system initialized (picks up where the last session left off)
- Codebase-pilot started indexing in the background
:::

---

## Minute 2: Ask about the codebase

> **You:** "what does this project do?"

:::note[Hook fires: exploring-codebase skill activates]
codebase-pilot queries its tree-sitter + SQLite index. No file-by-file reading — it answers from the structural index.
:::

**Claude responds:**

> "This is a TypeScript monorepo with 3 packages: `api` (Express REST API), `web` (Next.js frontend), and `shared` (types and utilities). The main entry point is `api/src/server.ts`. Authentication uses JWT stored in httpOnly cookies, with refresh logic in `api/src/middleware/auth.ts`. The frontend talks to the API through a generated client in `shared/src/api-client.ts`."

You just got a structural overview without reading a single file yourself. Try following up:

> **You:** "where does session expiry happen?"

> **Claude:** "Session expiry is in `api/src/middleware/auth.ts` line 47 — the `verifyToken` middleware rejects tokens older than the `SESSION_TTL` env var (default 30 minutes). The refresh endpoint is `POST /auth/refresh` handled in `api/src/routes/auth.ts` line 89."

---

## Minute 3: Watch a hook block something

> **You:** "rm -rf node_modules && rebuild"

:::caution[Hook fires: dangerous-bash validator blocks rm -rf]
The hook intercepts before the command runs. Claude sees the block and responds.
:::

**Claude responds:**

> "That command was blocked — `rm -rf` is flagged as destructive. To clean and reinstall dependencies: `rm -rf node_modules && npm install`. The rebuild alias you probably want is `npm run build`. Want me to run those?"

The hook didn't cancel your intent — it caught the destructive form and let Claude offer the safe equivalent. You never had to see the internals.

---

## Minute 4: Investigate a bug

> **You:** "this login function is broken, users get kicked after 5 minutes even with remember-me checked"

:::note[Hook fires: investigating-bugs skill activates]
Keyword "broken" triggers the skill. The 6-step protocol (REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM) starts automatically.
:::

**Claude responds:**

> "REPRODUCE: Let me find the session logic. Checking `auth.ts` and the remember-me flow... Found it. The `SESSION_TTL` is `300` (5 minutes) in `.env.development`. The remember-me flag sets a cookie but doesn't change the token TTL — both code paths call `signToken(userId)` with no duration override."
>
> "HYPOTHESIZE: The remember-me flag is written to the cookie but never read when signing the token. The fix is to pass a longer TTL when remember-me is true."
>
> "VERIFY: Confirmed — `signToken` in `shared/src/auth.ts:12` takes no duration argument. The remember-me value is stored in the cookie payload but ignored by the verifier."
>
> "FIX: I'll update `signToken` to accept an optional duration, then pass `30d` when remember-me is true."

For the full investigation protocol, see [Debug a Bug](../guides/debug-a-bug.md).

---

## Minute 5: Check what happened

```
/session-dashboard
```

**Claude responds with something like:**

```
Session Health — 4 min 12 sec

Hooks fired:         12  (8 validators, 4 lifecycle)
Hooks blocked:        1  (dangerous-bash: rm -rf)
Tool calls:          23  (22 success, 1 blocked)
Files read:           6
Files edited:         1
Edit churn:           0  (no immediate reverts)
Token efficiency:   94%
```

:::tip
Edit churn above 10% usually means Claude is guessing — it writes, reverts, rewrites. Zero churn here means the fix was targeted and confident.
:::

---

## What's next

- **Investigate bugs in depth** — [Debug a Bug](../guides/debug-a-bug.md)
- **Build a full feature** — [Build a Feature](../guides/build-a-feature.md)
- **Understand how it all fits** — [Core Concepts](core-concepts.md)
- **See all skills** — [Skills Reference](../../reference/skills/index.md)
