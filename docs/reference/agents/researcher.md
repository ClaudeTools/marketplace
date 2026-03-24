---
title: Researcher
parent: Agents
grand_parent: Reference
nav_order: 9
---

# Researcher

Research agent for external APIs, libraries, and documentation. Invoked before implementing code that touches external services.

## Purpose

Gathers verified, current information about external APIs, libraries, and documentation. Checks the local codebase first before going to the web — existing code and comments are faster and more reliable than web results. Verifies claims against multiple sources and is explicit about what was and was not confirmed.

## Model

`sonnet`

## Tool Access

Read-only: `Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput`

## Workflow

1. Checks the local codebase first:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js navigate "<query>"
```

2. If local knowledge is insufficient, searches the web via WebSearch and WebFetch
3. Collects sources with URLs for every claim
4. Cross-checks against multiple sources — never trusts a single source
5. Outputs structured findings with citations

## Research Focus

- **Current API documentation** — correct endpoint signatures, authentication, rate limits
- **Known issues and gotchas** — common failure modes, subtle behaviours
- **Breaking changes between versions** — what changed and when
- **Recommended patterns** — idiomatic usage, official examples

## Output Format

Findings are structured as:

- **Summary** — what was researched and the key conclusions
- **Verified facts** — each with at least one source URL
- **Unverified claims** — explicitly marked, with explanation of why they could not be confirmed
- **Sources** — full URL list

## When to Use

- Before implementing an integration with an external API
- When a library's API may have changed since it was last used
- When a dependency shows unexpected behaviour and you need to check its current documentation
- When choosing between two libraries and needing a current comparison

## Example Usage

```
Use the researcher agent to check the current Stripe API for how to handle subscription webhooks and any breaking changes in the v3 SDK.
```

The researcher checks if Stripe SDK usage exists locally first, then searches for the current webhook documentation, verifies the event types and signature verification pattern against multiple sources, and returns a cited findings report the implementing agent can act on.
