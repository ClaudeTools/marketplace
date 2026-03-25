---
title: "Security Pipeline"
description: "Read-only security audit pipeline — scans for secrets, injection vulnerabilities, dead controls, and CVEs with file:line evidence for every finding."
---

> **Status:** ✅ Stable — included in all claudetools versions

Read-only security audit pipeline. Runs a full codebase audit, security scan, and dead-code analysis to produce a structured security findings report.

## Purpose

Surfaces security findings across the entire codebase without modifying any files. Produces a severity-ordered report with file:line evidence for every finding. Does not fix issues — report only.

## Model

`sonnet`

## Tool Access

Read-only: `Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput`

## Workflow

### 1. Full Audit

Runs the full audit script for a broad picture of the codebase — architecture, dependencies, and surface area:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/full-audit.sh
```

### 2. Security Scan

Runs the security scan for targeted findings, grouped by severity:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/codebase-explorer/scripts/security-scan.sh
```

Covers: hardcoded secrets, SQL injection patterns, insecure crypto, console.log in production code, and unvalidated redirects.

### 3. Dead Code Check

Checks for unused security validators, hooks, or guards that may have been silently disabled:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js dead-code
```

### 4. Dependency Audit

```bash
npm audit --json 2>/dev/null || true
```

### 5. Generate Report

Produces a structured report with four sections:

1. **Critical Findings** — each with `[SEVERITY] file:line — description — evidence`
2. **Dead Security Controls** — validators/hooks/guards that exist but are not wired or called
3. **Dependency Vulnerabilities** — npm audit summary by severity
4. **Recommended Actions** — ordered by risk, with ownership recommendations

## When to Use

- Pre-release security review
- After a major refactor of auth, session, or data handling code
- When a dependency vulnerability report has been filed
- Periodic security posture assessment

## Constraints

- Never modifies any file — read-only audit only
- Never executes findings as fixes
- Every finding must have file:line evidence from the actual code
- Theoretical issues without code evidence are marked "unconfirmed"

## Example Usage

```
Run the security-pipeline agent before we cut the v2.0 release branch.
```

## Related

- [Run a Security Audit guide](/guides/run-security-audit/) — walkthrough of the security pipeline with real output
- [Reference: codebase-explorer skill](/reference/skills/codebase-explorer/) — the skill that powers the scan and dead-code steps
- [Bugfix Pipeline](bugfix-pipeline.md) — use after the audit to resolve critical findings
