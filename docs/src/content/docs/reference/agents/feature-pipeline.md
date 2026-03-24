---
title: "Feature Pipeline"
description: "Full-cycle feature pipeline — coordinates exploration, planning, parallel implementation, review, and verification for multi-file features."
---
Full-cycle feature development pipeline. Orchestrates exploration, planning, implementation, review, and verification end-to-end.

## Purpose

Coordinates the complete lifecycle of a new feature: understanding the codebase, forming a scoped plan, parallelising implementation across teammates, reviewing the output, and verifying correctness before declaring done. Use this agent when a feature touches multiple files or requires cross-cutting coordination.

## Model

`sonnet`

## Tool Access

Full access: `Glob, Grep, LS, Read, Edit, Write, NotebookRead, NotebookEdit, Bash, WebFetch, WebSearch, TodoWrite, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, KillShell, BashOutput`

## Workflow

### 1. Explore

Uses codebase-pilot to understand the area where the feature will land:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<feature-area>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<entry-file>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js file-overview "<entry-file>"
```

Reads actual source before forming a plan.

### 2. Plan

Uses the `/prompt-improver` skill to structure the implementation plan — breaking the feature into discrete, reviewable steps, identifying dependencies, and documenting the expected interface before writing any code.

### 3. Implement

Spawns `implementing-features` teammates, one per logical unit (e.g. data layer, UI layer). Coordinates shared decisions via agent-mesh:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --set "<decision-key>" "<value>"
```

### 4. Review

Runs a `code-reviewer` agent over the output with the list of changed files. Addresses all blocking findings before proceeding.

### 5. Verify

```bash
npx tsc --noEmit
./tests/run-tests.sh --file <changed-area>
```

All checks must pass before declaring the feature complete.

## When to Use

- Building a new feature end-to-end
- Feature requires changes in 3 or more files
- Feature has distinct layers (API, business logic, UI) that benefit from parallel implementation
- You need structured review and verification baked in

## Example Usage

```
Use the feature-pipeline agent to add rate limiting to the API endpoints.
```

The pipeline will explore the existing API structure, plan the implementation (middleware, config, tests), spawn teammates to build each layer, review the result, and verify typecheck and tests pass.
