---
title: "Explore a Codebase"
description: "Map an unfamiliar project's architecture, trace request flows, find dead code, and assess change blast radius using codebase-pilot."
sidebar:
  order: 5
---

**Difficulty: Beginner**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- [Core Concepts](../getting-started/core-concepts.md) — specifically the Codebase Pilot section
:::


Use codebase-pilot to navigate an unfamiliar project — map its structure, trace how a request flows, find dead code, and understand change blast radius — all through natural conversation.

## Starting out on a new project

> "I just joined this project, help me understand the architecture"

:::note[Behind the scenes]
`codebase-pilot map` runs at session start via `session-index.sh`, building a persistent index of symbols, files, and import graphs. The map command reads from this index — no re-parsing needed.
:::

```
## Project Map

Languages:  TypeScript (82%), SQL (11%), Shell (7%)
Entry points:
  - src/server.ts          — Express app bootstrap
  - src/worker.ts          — Background job processor

Key directories:
  src/api/        — Route handlers (12 files)
  src/services/   — Business logic (8 files)
  src/db/         — Knex migrations + query builders (15 files)
  src/jobs/       — Bull queue job definitions (6 files)
  src/middleware/  — Auth, rate-limit, validation (4 files)

Exports with wide usage (>5 importers):
  src/db/client.ts         → db (knex instance)
  src/services/auth.ts     → verifyToken, createSession
  src/config/index.ts      → config
```

Now you have enough orientation to ask specific questions.

---

## Following a request path

> "how does the /api/users endpoint work?"

Claude chains three tools to trace the full path:

:::note[Behind the scenes]
1. `find-route.sh "/api/users"` locates the route registration
2. `file-overview src/api/users.ts` lists all symbols in the handler file
3. `related-files src/api/users.ts` shows what the handler imports and what imports it
:::

```
Route: GET /api/users
  Registered:  src/server.ts:44
  Middleware:  requireAuth → rateLimiter (src/middleware/)
  Handler:     src/api/users.ts → listUsers()

Handler: listUsers() [src/api/users.ts:23]
  Calls:
    - db.select() from src/db/client.ts
    - validatePaginationParams() from src/middleware/validation.ts
    - formatUserResponse() from src/services/users.ts

Callers of src/api/users.ts:
  - src/server.ts (route registration only)
  - tests/api/users.test.ts
```

You can now read `src/api/users.ts` and `src/services/users.ts` with full context.

---

## Finding a specific symbol

> "what does handleAuth do?"

:::note[Behind the scenes]
`find-symbol "handleAuth"` searches the symbol index. Claude then runs `file-overview` on the containing file to show surrounding context.
:::

```
handleAuth  [function]
  Defined:  src/middleware/auth.ts:18
  Exported: yes

  src/middleware/auth.ts exports:
    - handleAuth(req, res, next)   — JWT verification middleware
    - requireRole(role)            — Role-check factory
    - extractUserId(req)           — Helper, reads from req.auth
```

---

## Tracing a field through the codebase

> "where does amount_due get transformed?"

:::note[Behind the scenes]
`trace-field.sh "amount_due"` scans for the field across all files and groups hits by role: definition, transforms, SQL queries, and frontend rendering.
:::

```
Field: amount_due

Definitions:
  src/db/migrations/003_invoices.ts:31   — decimal(10,2) NOT NULL
  src/types/invoice.ts:12                — amountDue: number

Transforms:
  src/services/invoices.ts:67   — computed from lineItems.reduce(...)
  src/jobs/sync.ts:103          — converted from cents (÷ 100) on ingest

SQL queries:
  src/db/invoices.ts:45   — SELECT amount_due FROM invoices WHERE ...
  src/db/reports.ts:88    — SUM(amount_due) GROUP BY customer_id

Display:
  src/components/InvoiceTable.tsx:34   — formatCurrency(invoice.amountDue)
```

---

## Finding dead code

> "anything unused I should clean up?"

:::note[Behind the scenes]
`codebase-pilot dead-code` cross-references the import graph against all exported symbols. It only flags exports that have zero importers — unexported dead code is not included.
:::

```
Unused exports (no importers found):

  src/utils/legacy-csv.ts
    exportToCSVv1()   — last modified 4 months ago

  src/services/notifications.ts
    sendPushNotification()   — imported in 0 files
    PUSH_RETRY_LIMIT         — imported in 0 files

  src/api/internal.ts
    debugDumpState()   — likely debug artifact
```

---

## Impact analysis before a refactor

> "what breaks if I change the User model?"

:::note[Behind the scenes]
`codebase-pilot change-impact "User"` walks the import graph from the symbol outward, separating direct importers from test files and indirect dependents.
:::

```
Change impact: User (src/types/user.ts)

Direct importers (must update):
  src/services/auth.ts:12
  src/api/users.ts:5
  src/db/users.ts:8
  src/services/billing.ts:31

Indirect dependents (may be affected):
  src/jobs/invoice-sync.ts   — imports billing.ts
  src/api/invoices.ts        — imports billing.ts

Test files:
  tests/services/auth.test.ts
  tests/api/users.test.ts

Blast radius: 4 direct, 2 indirect, 2 test files
```

---

:::tip[When to use what]
- **"What does X do?"** — `find-symbol` → `file-overview` gives you definition + context
- **"What uses X?"** — `find-usages` lists all call sites across the codebase
- **"What imports from Y?"** — `related-files` shows the full import neighbourhood
- **"Are there circular dependencies?"** — ask "any circular deps?" and Claude runs `circular-deps`
- **"What's safe to delete?"** — ask "any dead code?" and Claude runs `dead-code`
:::

## Tips

- Start every unfamiliar codebase with `map` — the overview guides every subsequent query
- For a bug investigation: `find-symbol` (locate the source) → `file-overview` (context) → `find-usages` (all call sites)
- Run `change-impact` before any refactor touching exported symbols — know the blast radius first
- If results seem stale after editing, say "reindex the codebase" — Claude triggers a full rebuild

## Related

- [Debug a Bug](debug-a-bug.md) — uses explore modes as part of the OBSERVE step
- [Build a Feature](build-a-feature.md) — feature-pipeline runs exploration before planning
- [Run a Security Audit](run-security-audit.md) — security-scan mode finds vulnerabilities
