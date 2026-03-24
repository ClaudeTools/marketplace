---
title: "Run a Security Audit"
description: "Run a Security Audit — claudetools documentation."
---
Use the security-pipeline agent for a full codebase audit, or the exploring-codebase security-scan mode for a targeted check — producing structured findings with file:line evidence for every issue.


## What you need
- claudetools installed
- A project with Node.js dependencies (for the npm audit step)

## Steps

### Option A — Full audit with the security-pipeline agent

For a comprehensive audit of the whole codebase:

```
/claudetools:security-pipeline
```

The pipeline is read-only — it produces a findings report but never modifies files.

**Step 1: Full audit**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/full-audit.sh
```

Covers architecture overview, dependency surface area, and entry points.

**Step 2: Security scan**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/security-scan.sh
```

AST-aware scanning that finds:
- Hardcoded secrets (API keys, tokens, passwords)
- SQL injection (string interpolation in query calls)
- Insecure crypto (MD5, SHA1, weak algorithms)
- `console.log` calls in production code paths
- Unvalidated redirects

Findings are grouped by severity: CRITICAL, HIGH, MEDIUM, LOW.

**Step 3: Dead security controls check**

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js dead-code
```

Flags security-related files (validators, guards, hooks) that exist but are not wired up or being called.

**Step 4: Dependency vulnerability audit**

```bash
npm audit --json
```

Summarised by severity with affected packages and recommended actions.

**Step 5: Structured report**

The pipeline produces a four-section report:

```
Section 1 — Critical Findings
[CRITICAL] src/api/users.ts:42 — SQL injection — user input reaches query via string interpolation

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

Every finding includes file:line evidence from the actual code. Theoretical issues without evidence are marked "unconfirmed" with an explanation.

### Option B — Quick security scan

For a targeted check on a specific concern:

```
scan for security issues
```

or

```
check for hardcoded secrets
```

Claude uses the exploring-codebase security-scan mode:

```bash
# Default: CRITICAL and HIGH only
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/security-scan.sh

# Show all severities
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/security-scan.sh --all

# JSON output for piping
bash ${CLAUDE_PLUGIN_ROOT}/skills/exploring-codebase/scripts/security-scan.sh --json
```

### Acting on findings

The security-pipeline produces findings only — it does not fix them. To address findings:

1. Review the report and prioritize by severity
2. Use `/managing-tasks new` to create tracked tasks for each fix
3. Use the debug-a-bug workflow for security fixes that require root-cause investigation
4. Re-run the security scan after fixes to verify resolution

## What happens behind the scenes

- **security-scan.sh** uses grep with AST-aware patterns — it filters out safe patterns (e.g., `process.env` lookups) before flagging potential secrets, reducing false positives
- **full-audit.sh** runs all analysis commands in a single pass to avoid redundant parsing
- **codebase-pilot dead-code** uses the import graph to find security controls that are defined but never referenced — a common source of "defense that doesn't exist"
- The pipeline is **read-only** — no files are modified, no fixes are applied, no commands with side effects are run

## Tips

- Run a full audit before any major release or after a large dependency upgrade
- Use the quick scan during development to catch issues as they are introduced
- The dead security controls check is often overlooked — a validator that is never called is as dangerous as one that doesn't exist
- Share the findings report with `git add audit-report.md && git commit` so the team has a baseline to track improvements against
- Fix CRITICAL findings before HIGH, HIGH before MEDIUM — severity reflects the actual risk of exploitation

## Related

- [Debug a Bug](debug-a-bug.md) — investigate a security finding with evidence-based root cause analysis
- [Review Code](review-code.md) — Pass 2 of code-review covers security for changed files
- [Explore a Codebase](explore-a-codebase.md) — security-scan and dead-code are available as standalone modes
