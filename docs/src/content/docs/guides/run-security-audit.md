---
title: "Run a Security Audit"
description: "Scan for secrets, injection vulnerabilities, dead security controls, and dependency CVEs — with file:line evidence for every finding."
---

**Difficulty: Advanced**

:::note[Prerequisites]
- [claudetools installed](../getting-started/installation.md) — plugin active in Claude Code
- [Core Concepts](../getting-started/core-concepts.md) — understanding agents and the security-pipeline
- [Explore a Codebase](explore-a-codebase.md) — security-scan and dead-code use the same codebase-pilot tooling
:::


Use the security-pipeline agent for a full codebase audit, or ask Claude directly for a targeted check — producing structured findings with `file:line` evidence for every issue.

## Real scenarios

### Scenario A: Quick scan during development

> "check this project for security issues"

:::note[Behind the scenes]
The codebase-explorer skill detects the security intent and runs `security-scan.sh` automatically. No command needed — Claude recognises the request and acts.
:::

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/security-scan.sh
```

```
Security scan complete — 3 findings

[CRITICAL] src/api/users.ts:42
  SQL injection — user input reaches query via string interpolation
  req.query.search is passed directly into `WHERE name LIKE '${search}'`
  Fix: use parameterised query with $1 placeholder

[HIGH] src/config/database.ts:8
  Hardcoded credential — DB_PASSWORD set as string literal
  Fix: move to environment variable

[MEDIUM] src/api/auth.ts:103
  console.log prints req.body on login attempts — includes password field in logs
  Fix: remove or replace with structured logger that strips sensitive fields
```

Every finding includes the file and line number so you can jump directly to the issue.

---

### Scenario B: Specific concern

> "check for hardcoded secrets"

Claude runs the scan with a focused filter:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/security-scan.sh --secrets-only
```

```
Secrets scan — 2 findings

[CRITICAL] src/config/database.ts:8
  DB_PASSWORD = "prod-db-pass-2024"

[HIGH] tests/fixtures/seed.ts:31
  API_KEY = "sk-test-abc123..." — test fixture key, but pattern matches production format
  Confirm this is a test key and rotate if there is any chance it reached production
```

---

### Scenario C: Full audit with the security-pipeline agent

> "spawn a security-pipeline agent and run a full audit"

:::note[Behind the scenes]
The security-pipeline agent runs five steps in sequence, each feeding context into the next. The pipeline is read-only — it produces findings but never modifies files.
:::

**Step 1 — Full audit**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/full-audit.sh
```

Covers architecture overview, dependency surface area, and entry points — establishing what exists before scanning for what's wrong.

**Step 2 — Security scan**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/security-scan.sh --all
```

AST-aware scanning across all severity levels:
- Hardcoded secrets (API keys, tokens, passwords)
- SQL injection (string interpolation in query calls)
- Insecure crypto (MD5, SHA1, weak algorithms)
- `console.log` in production code paths
- Unvalidated redirects

**Step 3 — Dead security controls**

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js dead-code
```

Flags security-related files that exist but are never called — validators, guards, sanitizers that were written but not wired up. A validator that is never invoked is as dangerous as one that doesn't exist.

```
Dead security controls — 1 finding

src/validators/input-sanitizer.ts
  Exported: sanitizeInput(), validateSchema()
  Imported in: nowhere
  Status: defined but never called in production code paths
```

**Step 4 — Dependency audit**

```bash
npm audit --json
```

**Step 5 — Structured report**

```
Security Audit Report — 2026-03-24

Section 1 — Critical Findings
[CRITICAL] src/api/users.ts:42 — SQL injection — user input reaches query via string interpolation
[CRITICAL] node_modules/lodash@4.17.15 — prototype pollution (CVE-2021-23337)

Section 2 — Dead Security Controls
src/validators/input-sanitizer.ts — exported but never imported in production code

Section 3 — Dependency Vulnerabilities
2 critical (prototype-pollution in lodash 4.17.15)
1 high (ReDoS in validator 13.6.0)

Section 4 — Recommended Actions
1. Fix SQL injection in users.ts (CRITICAL — auth bypass risk)
2. Wire input-sanitizer.ts into API middleware (HIGH — all inputs currently unvalidated)
3. Upgrade lodash to 4.17.21 (CRITICAL — supply chain risk)
```

---

### Acting on findings

The security-pipeline produces findings only — it does not apply fixes. To address findings:

> "create tasks for the critical and high findings from the security audit"

```
Created:
  task-sec-001  Fix SQL injection in src/api/users.ts:42         [critical]
  task-sec-002  Wire input-sanitizer.ts into API middleware       [high]
  task-sec-003  Upgrade lodash to 4.17.21                         [critical]
```

Then work through them:

> "/task-manager start"

---

:::tip[Quick scan vs full pipeline]
- **Quick scan**: Ask "check for security issues" or "any hardcoded secrets?" — Claude runs `security-scan.sh` automatically, results in under 30 seconds
- **Full audit**: Say "spawn a security-pipeline agent" — four-step analysis including dead security controls and dependency CVEs, takes 2–5 minutes
- **Pre-release**: Always run the full pipeline before a major release or after a large dependency upgrade
- **During development**: Run the quick scan after touching auth, database queries, or user input handling
:::

## What happens behind the scenes

- **security-scan.sh** uses grep with AST-aware patterns — it filters out safe patterns (e.g. `process.env` lookups) before flagging potential secrets, reducing false positives significantly
- **full-audit.sh** runs all analysis commands in a single pass to avoid redundant file parsing
- **codebase-pilot dead-code** uses the import graph to find security controls that are defined but never referenced
- The pipeline is **read-only** — no files are modified, no fixes applied, no commands with side effects run

## Tips

- The dead security controls check is often overlooked — run it before every release, not just after a new feature
- Fix CRITICAL before HIGH, HIGH before MEDIUM — severity reflects actual exploitation risk
- Save the findings report to git (`git add audit-report.md && git commit`) so the team has a baseline to track improvements against

## Related

- [Debug a Bug](debug-a-bug.md) — investigate a security finding with evidence-based root cause analysis
- [Review Code](review-code.md) — Pass 2 of code-review covers security for changed files
- [Explore a Codebase](explore-a-codebase.md) — security-scan and dead-code are available as standalone modes
