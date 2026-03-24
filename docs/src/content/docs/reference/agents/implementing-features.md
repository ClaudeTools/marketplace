---
title: "Implementing Features"
description: "Implementation agent for multi-file code changes — reads widely before editing, tracks work in tasks, and verifies correctness after every change."
---
Implementation agent for building features and making multi-file code changes.

## Purpose

Builds features methodically with full verification. The workhorse agent for writing code — reads widely before touching anything, tracks work in tasks, commits incrementally, and verifies correctness after each change.

## Model

`sonnet`

## Tool Access

Full access: `Glob, Grep, LS, Read, Edit, Write, NotebookRead, NotebookEdit, Bash, WebFetch, WebSearch, TodoWrite, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, KillShell, BashOutput`

## Workflow

### Before Coding

- Runs `codebase-pilot map` to understand project structure
- Uses `file-overview` and `related-files` on files to be modified
- Checks MEMORY.md for stored preferences that affect the approach

### During Implementation

- Creates a task for each logical unit before starting (`TaskCreate`)
- Marks tasks `in_progress` when starting, `completed` when done
- Uses conventional commits after each completed task
- Runs typecheck after every file change
- Runs tests before committing

### After Coding

- Re-reads every changed file to verify no stubs, placeholders, or type escapes remain
- Runs the full relevant test suite
- Verifies no regressions in existing functionality

## When to Use

- Implementing new functionality across multiple files
- Making structural code changes as part of a larger plan
- As a teammate spawned by a pipeline agent (feature-pipeline, bugfix-pipeline, refactor-pipeline)
- Any time code needs to be written with task tracking and verification built in

## Example Usage

```
Use the implementing-features agent to add pagination to the /api/invoices endpoint. The endpoint is in src/routes/invoices.ts and the response type is in src/types/invoice.ts.
```

The agent reads the existing route, understands the response shape, creates tasks for the implementation steps, makes the changes, runs typecheck, runs targeted tests, and commits with a `feat:` message.
