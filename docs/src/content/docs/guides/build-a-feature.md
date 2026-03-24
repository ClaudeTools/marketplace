---
title: "Build a Feature"
description: "Walk through a real feature build — task creation, parallel implementation, quality hooks, and verification."
---

**Difficulty: Intermediate**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- [Core Concepts](../getting-started/core-concepts.md) — understanding agents, skills, and the task system
- [Manage Tasks](manage-tasks.md) — the pipeline creates and tracks tasks automatically
:::


A realistic walkthrough of building a medium-complexity feature end-to-end. See what Claude actually does at each stage.

:::tip[When to use what]
- **Small feature** (1-2 files, clear scope): Just ask Claude directly — it will implement without needing a pipeline
- **Medium feature** (3-10 files): Use `/prompt-improver` to structure the task, then execute directly
- **Large feature** (10+ files, multiple concerns): Spawn the `feature-pipeline` agent — it handles explore, plan, parallel implementation, review, and verify
:::

---

## The feature

> **You:** "Add a notification system — users should get an email when their order ships"

This touches at least three layers: a notification service, an email template, and a trigger in the order fulfillment flow. That's large enough to benefit from the pipeline.

---

## Step 1 — Create a task first

> **You:** `/task-manager new Add email notification when order ships`

:::note[Hook fires: task-manager skill activates]
The skill queries codebase-pilot to enrich the task before saving it.
:::

**Claude responds:**

> "Task created: `task-a4f2`. Enriched with codebase context:
>
> - Fulfillment trigger point: `OrderService.markShipped()` in `api/src/services/order-service.ts:142`
> - Email infrastructure: `lib/mailer.ts` (uses Nodemailer, SMTP configured)
> - Existing notification pattern: `NotificationService` in `api/src/services/notification-service.ts` (SMS only)
> - Acceptance criteria added: email sent within 5s of `markShipped`, contains tracking number, unsubscribe link included
>
> Review the task? Or spawn the feature pipeline?"

:::tip
Always create the task before spawning the pipeline. The enriched task description becomes the pipeline's specification — without it, the pipeline works from your raw description alone.
:::

---

## Step 2 — Spawn the feature pipeline

> **You:** `/claudetools:feature-pipeline task-a4f2`

The pipeline takes over. You interact with it as a single agent — it coordinates everything below the surface.

---

## Step 3 — EXPLORE

The pipeline runs codebase-pilot to map the area:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "NotificationService"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "api/src/services/order-service.ts"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map --entry "api/src/services/"
```

> "EXPLORE complete. Key findings:
> - `NotificationService` exists but only sends SMS. The email channel is missing.
> - `markShipped()` emits an `order.shipped` domain event — perfect hook point, no new trigger needed.
> - `lib/mailer.ts` has a `sendTemplate(to, template, vars)` method. I just need a template.
> - Tests live in `tests/services/` — one test file per service."

---

## Step 4 — PLAN

> "PLAN: Breaking into 3 independent units:
>
> 1. **Email template** — `templates/order-shipped.html` + `templates/order-shipped.txt`
> 2. **NotificationService email channel** — extend `notification-service.ts` to handle `email` channel
> 3. **Event wiring** — subscribe `NotificationService.sendShipmentEmail` to the `order.shipped` event
>
> Dependencies: (1) and (2) are parallel. (3) blocks on both.
>
> Confirm this plan before I implement?"

> **You:** "yes, go ahead"

---

## Step 5 — IMPLEMENT (parallel)

The pipeline spawns two implementing-features teammates via TeamCreate:

**Teammate A** — notification service email channel:
- Reads `notification-service.ts`, adds `sendShipmentEmail(order)`
- Calls `mailer.sendTemplate` with the template name and order variables
- Shares the template variable schema via agent-mesh:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --set "shipment-template-vars" '{"orderId","trackingNumber","customerName","unsubscribeToken"}'
```

**Teammate B** — email templates:
- Reads agent-mesh context to get the variable schema
- Creates `templates/order-shipped.html` and `.txt` with the correct variables
- No coordination needed — the schema is the contract

:::note[Hook fires mid-implementation: stub detection]
Teammate A writes `sendShipmentEmail` as a stub while scaffolding. The stub-detection hook fires:
> "Stub detected: `sendShipmentEmail` has no implementation body. Complete the implementation before proceeding."

Teammate A fills in the implementation before continuing.
:::

After both complete, Teammate C wires the event subscription — reads both outputs, connects `order.shipped` to `sendShipmentEmail`.

---

## Step 6 — REVIEW

A code-reviewer agent runs over all changed files:

> "Review findings (3 total, 1 blocking):
>
> - **[BLOCK]** `notification-service.ts:89` — `sendShipmentEmail` doesn't handle mailer errors. If SMTP fails, the exception propagates unhandled and will crash the order fulfillment flow.
> - `templates/order-shipped.html:12` — unsubscribe link uses a hardcoded domain. Should use `process.env.APP_URL`.
> - `tests/notification-service.test.ts` — test for email channel missing. SMS tests exist, email tests don't."

The pipeline holds until the blocking finding is resolved. Teammate A wraps the mailer call in try/catch and logs the failure without rethrowing.

---

## Step 7 — VERIFY

```bash
npx tsc --noEmit
./tests/run-tests.sh --file notification-service
./tests/run-tests.sh --file order-service
```

> "VERIFY: Typecheck passes. 6 notification-service tests pass (4 SMS, 2 new email). Order-service tests unaffected. Feature complete."

---

## The result

Three files created, two files modified, six tests passing. The entire flow from prompt to verified feature ran through one pipeline agent — you only made two decisions: confirm the plan, and read the review findings.

---

## Related

- [Manage Tasks](manage-tasks.md) — create and track feature tasks before building
- [Review Code](review-code.md) — run a standalone code review on any output
- [Coordinate Agents](coordinate-agents.md) — understand how TeamCreate teammates share decisions
- [Reference: feature-pipeline agent](../../reference/agents/feature-pipeline.md)
