---
name: research
description: >
  Research external APIs, libraries, and documentation before implementing code
  that touches external services. Enforces a research-first workflow so code is
  written against current, verified information — not stale assumptions.
argument-hint: "[topic, API, or library to research]"
allowed-tools: Glob, Grep, Read, WebSearch, WebFetch, Bash, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [research, documentation, API, libraries, external]
---

# Research Before Implementation

> HARD GATE: Do NOT write implementation code that calls external APIs, uses
> unfamiliar libraries, or touches systems you haven't verified. Research first,
> implement second. Guessing at API signatures wastes more time than reading docs.

## When to Use

- Before implementing code that calls external APIs (Stripe, AWS, Xero, etc.)
- Before using a library or framework you haven't worked with in this project
- When a task mentions specific versions, endpoints, or SDK methods
- When the `research-backing` validator has blocked your code (fix the root cause, not the symptom)

## The Protocol

### Step 1: Identify what needs research

List every external dependency the task touches:
- APIs: which endpoints, what authentication, what rate limits?
- Libraries: which version is installed, what's the current API?
- Services: what configuration is needed, what are the failure modes?

### Step 2: Find current documentation

Use WebSearch and WebFetch to find authoritative docs:

1. **Official docs first** — `site:docs.stripe.com`, `site:developer.xero.com`, etc.
2. **SDK source** — check the installed version: `npm list <package>` or `pip show <package>`
3. **Changelog** — if upgrading, read what changed between versions

### Step 3: Verify assumptions

For each API endpoint or method you plan to use:
- Does it exist in the current version?
- What are the required parameters?
- What does the response look like?
- What errors can it return?

### Step 4: Document findings

Create a brief summary of what you found. This becomes context for implementation:
- Endpoint URLs and methods
- Required headers/auth
- Request/response shapes
- Rate limits or quotas
- Known gotchas

### Step 5: Proceed to implementation

Only after Steps 1-4 are complete. Reference your findings as you write code.

## Anti-Patterns

| Excuse | Reality |
|--------|---------|
| "I know this API" | You know the version from your training data. The current version may differ. |
| "I'll check if it fails" | Fail-then-fix costs 3x more than research-then-implement. |
| "The docs are probably the same" | APIs change. Endpoints get deprecated. Auth methods rotate. |
| "It's just a small call" | Small calls with wrong auth or wrong endpoints waste debugging time. |
