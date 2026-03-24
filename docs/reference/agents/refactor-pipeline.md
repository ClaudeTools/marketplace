---
title: Refactor Pipeline
parent: Agents
grand_parent: Reference
nav_order: 4
---

# Refactor Pipeline

Safe refactor pipeline. Orchestrates change-impact analysis, step decomposition, parallel implementation, and regression verification.

## Purpose

Coordinates safe, incremental refactoring of shared or cross-cutting code. Requires full impact analysis before any code changes, decomposes the refactor into independently verifiable steps, and enforces zero regressions as the exit criterion.

## Model

`sonnet`

## Tool Access

Full access: `Glob, Grep, LS, Read, Edit, Write, NotebookRead, NotebookEdit, Bash, WebFetch, WebSearch, TodoWrite, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, KillShell, BashOutput`

## Workflow

### 1. Explore and Impact Analysis

Uses codebase-pilot to understand the full blast radius before touching anything:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js change-impact "<symbol>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-usages "<symbol>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js circular-deps
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js api-surface
```

Reads the code at all impact sites before proceeding.

### 2. Decompose

Uses the `/improving-prompts` skill to decompose the refactor into safe, independently verifiable steps:

- Each step must be testable in isolation
- Steps are ordered to avoid breaking intermediate states (add new → migrate callers → remove old)
- Parallel steps are identified (no shared write targets)
- Rollback plan is documented for each step

### 3. Implement (Parallel)

Spawns `implementing-features` teammates — one per independent step. Sequential steps wait for the prior step to complete. Shared decisions are coordinated via agent-mesh:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --set "<refactor-key>" "<decision>"
```

### 4. Verify

```bash
npx tsc --noEmit
./tests/run-tests.sh <affected-category>
./tests/run-tests.sh <related-category>
```

All checks must pass with zero regressions.

## When to Use

- Renaming or moving a symbol used across many files
- Changing a shared interface or function signature
- Extracting a module from a monolithic file
- Migrating from one library or pattern to another across the codebase

## Constraints

- Always run change-impact analysis before writing any code
- Never start implementation without a decomposed step plan
- Never merge steps with overlapping write targets — sequence them
- Zero regressions is the exit criterion

## Example Usage

```
Use the refactor-pipeline agent to rename UserRecord to UserProfile across the entire codebase.
```
