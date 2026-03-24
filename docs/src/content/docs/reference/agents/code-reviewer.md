---
title: "Code Reviewer"
description: "Code Reviewer — claudetools documentation."
---
Read-only code review agent. Invoked for structured code quality review without modifying files.

## Purpose

Reviews code changes for correctness, security, performance, and maintainability. Uses codebase-pilot to understand the broader context before flagging issues — a pattern that looks wrong in isolation may be correct given its callers or dependents.

## Model

`sonnet`

## Tool Access

Read-only: `Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput`

## Workflow

1. Runs `codebase-pilot map` to get a project overview
2. Uses `file-overview` on each changed file to understand its role and exports
3. Uses `related-files` to see what depends on the changed code
4. Uses `find-usages` on changed symbols to assess blast radius
5. Reads the actual changed code
6. Produces structured findings with `file:line` references

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "<path>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<path>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-usages "<symbol>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<name>"
```

## Review Focus

- **Correctness** — logic errors, edge cases, off-by-one errors
- **Security** — injection vulnerabilities, authentication gaps, credential handling
- **Performance** — N+1 queries, unnecessary allocations, blocking calls in hot paths
- **Maintainability** — readability, coupling, naming clarity

Every finding includes a `file:line` reference. The review always includes positive observations about what was done well alongside issues.

## When to Use

- After a pipeline agent (feature-pipeline, bugfix-pipeline) completes its implementation step
- Before merging a PR to get a second opinion
- When a change touches security-sensitive code
- As a lightweight audit without the full security-pipeline overhead

## Example Usage

```
Use the code-reviewer agent to review the changes in src/auth/ and src/middleware/session.ts.
```

The reviewer checks the auth changes for correctness and security issues, traces how session.ts is used across the codebase, and returns a structured report with severity-tagged findings and file:line references.
