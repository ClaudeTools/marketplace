---
title: "Quick Tour"
description: "Your first five minutes with claudetools — real prompts, real responses, real guardrails."
sidebar:
  order: 2
---

A narrated walkthrough of your first five minutes. Every prompt is something you'd actually type. Every response is what you'd actually see.

---

## Minute 1: Install and open a session

```
/plugin install claudetools@claudetools-marketplace
```

Open a new Claude Code session. You won't see a splash screen — claudetools is silent when everything works.

:::note[What just happened]
Behind the scenes, claudetools set up three things: a set of safety guardrails that run on every command, a memory system that picks up where your last session left off, and a background scan of your project files so Claude can answer structural questions quickly. Nothing to configure.
:::

<details>
<summary>What exactly runs at session start? (Advanced)</summary>

When you open a Claude Code session with claudetools installed:

1. **51 hooks register** across 17 lifecycle events (`PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, and more). Each hook is a shell script that fires automatically — you don't invoke them.
2. **Skills load** — 7 structured workflows become available, either auto-triggered by Claude or invoked via `/skill-name`.
3. **`session-index.sh` runs** in the background — it calls `codebase-pilot index` to build or update a tree-sitter + SQLite symbol index of your project. For large projects this takes 10–30 seconds. You won't see it happen.

</details>

**Try it yourself:** After installing, open a new session and try one of the prompts in Minute 2 below.

---

## Minute 2: Ask about the codebase

> **You:** "what does this project do?"

claudetools builds a map of your project's structure — files, functions, and how they connect — so Claude can answer architectural questions without reading every file one by one. The result is faster, more accurate answers.

**Claude responds:**

> "This is a TypeScript monorepo with 3 packages: `api` (Express REST API), `web` (Next.js frontend), and `shared` (types and utilities). The main entry point is `api/src/server.ts`. Authentication uses JWT stored in httpOnly cookies, with refresh logic in `api/src/middleware/auth.ts`. The frontend communicates with the API through a generated client in `shared/src/api-client.ts`."

You got a structural overview without reading a single file yourself. Try following up:

> **You:** "where does session expiry happen?"

> **Claude:** "Session expiry is in `api/src/middleware/auth.ts` line 47 — the `verifyToken` middleware rejects tokens older than the `SESSION_TTL` env var (default 30 minutes). The refresh endpoint is `POST /auth/refresh` in `api/src/routes/auth.ts` line 89."

**Try it yourself — copy one of these:**

```
what does this project do?
```
```
give me a map of the main files and what each one is responsible for
```

*Python project:*
```
what's the entry point for this Flask app and how are routes organized?
```
```
explain how this Django project handles authentication
```

*Node.js project:*
```
walk me through how a request flows from the Express router to the database
```
```
where is error handling centralized in this project?
```

---

## Minute 3: Watch a guardrail catch something

> **You:** "delete node_modules and rebuild everything"

Before any command runs, claudetools checks it for safety. If it looks destructive — like a recursive delete — it's blocked before anything happens, and Claude is told why so it can offer a safer alternative.

**Claude responds:**

> "That command was blocked — `rm -rf` is flagged as destructive. To clean and reinstall: `rm -rf node_modules && npm install`. The rebuild you probably want is `npm run build`. Want me to run those?"

Your intent was understood. The unsafe form was caught. You didn't lose anything.

**Try it yourself — these are intentionally caught:**

```
delete node_modules and rebuild everything
```
```
force push my changes to main
```

*Python project:*
```
wipe the virtualenv and reinstall dependencies
```
```
drop the test database and recreate it from migrations
```

*Node.js project:*
```
clear all build artifacts and start fresh
```
```
remove the lock file and reinstall everything
```

:::tip
You're not expected to avoid these phrasings. The guardrail catches the unsafe form, tells Claude why, and Claude offers the safe equivalent. You keep your intent; the risky part doesn't run.
:::

---

## Minute 4: Investigate a bug

> **You:** "users get kicked out after 5 minutes even with remember-me checked"

When you describe a bug, claudetools guides Claude through a structured process: first find and reproduce the problem in the code, then investigate what's actually happening, form a hypothesis about the cause, verify it, fix it, and confirm the fix works. This prevents the common pattern of guessing a fix without understanding the problem first.

**Claude responds:**

> "Let me find the session logic. Checking `auth.ts` and the remember-me flow..."
>
> "Found it. The session timeout is set to 300 seconds (5 minutes) in `.env.development`. The remember-me flag writes to the cookie but doesn't change how long the session token is valid — both paths call `signToken(userId)` with no duration override."
>
> "The fix: `signToken` needs to accept an optional duration. When remember-me is true, pass `30d` instead of the default. I'll make that change now."

For the full investigation workflow, see [Debug a Bug](../guides/debug-a-bug.md).

**Try it yourself — describe a real bug:**

```
users get kicked out after 5 minutes even with remember-me checked
```
```
the search results are wrong — it's returning items from the wrong category
```

*Python project:*
```
the API returns 500 when the request body is missing a field, instead of a 400
```
```
the background task runs but the database never gets updated
```

*Node.js project:*
```
the webhook handler processes the same event twice sometimes
```
```
the cache isn't being invalidated when a record is updated
```

---

## Minute 5: Check what happened

```
/session-dashboard
```

At the end of any session you can get a plain-English summary of what happened — which files were touched, whether any unsafe commands were caught, and a rough efficiency signal.

**Claude responds with something like:**

```
Session Health — 4 min 12 sec

Commands checked:    12
Commands blocked:     1  (rm -rf → offered safe alternative)
Files read:           6
Files edited:         1
Wasted edits:         0  (no write → revert → rewrite cycles detected)
```

:::tip[What "wasted edits" means]
A wasted edit is when Claude writes something, immediately changes its mind, and rewrites it — a sign it was guessing rather than reasoning. Zero here means every edit was intentional. If this number is high, try giving Claude more context before it starts writing.
:::

---

## What's next

- **Debug a bug in depth** — [Debug a Bug](../guides/debug-a-bug.md)
- **Build a feature end to end** — [Build a Feature](../guides/build-a-feature.md)
- **Understand how it all fits together** — [Core Concepts](core-concepts.md)
- **See every available skill** — [Skills Reference](../../reference/skills/)
