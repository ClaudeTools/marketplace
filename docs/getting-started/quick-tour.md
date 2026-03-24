---
title: Quick Tour
parent: Getting Started
nav_order: 2
---

# Quick Tour

A walkthrough of your first five minutes with claudetools.

---

## Step 1: Install and open a session

```
/plugin install claudetools@claudetools-marketplace
```

Open a new Claude Code session. In the background:

- All 51 hooks register across 17 lifecycle events
- The memory system initializes
- Codebase indexing starts (runs once at session open)

You won't see any of this unless something gets blocked.

---

## Step 2: Explore the codebase

Try a prompt like:

> "Walk me through how authentication works in this codebase."

The **exploring-codebase** skill activates automatically. Behind the scenes:

- **codebase-pilot** queries its tree-sitter + SQLite index
- Finds relevant symbols, traces import chains, maps module boundaries
- Returns a structured answer grounded in actual code — not guesses

You can also invoke it directly: `/exploring-codebase`

---

## Step 3: Investigate a bug

Try:

> "There's a bug where users get logged out after 30 minutes even with 'remember me' checked. Find it."

The **investigating-bugs** skill activates and runs a 6-step protocol:

1. **Reproduce** — locate the code path responsible
2. **Observe** — surface what the code actually does
3. **Hypothesize** — form a specific, testable explanation
4. **Verify** — confirm the hypothesis before touching anything
5. **Fix** — make the minimal change
6. **Confirm** — check that the fix resolves the original symptom

The two-strike rule applies: if two hypotheses fail, the skill re-examines assumptions before continuing.

---

## Step 4: Check the session dashboard

```
/session-dashboard
```

You'll see a system health report including:

- Hook fire and block rates by category
- Tool success/failure breakdown
- Edit churn (how often edits were immediately reverted)
- Token efficiency metrics

This tells you how much work the hooks are doing invisibly on your behalf.

---

## Step 5: Check memory

```
/memory
```

claudetools accumulates cross-session knowledge: project conventions, recurring patterns, decisions made. The memory system uses FTS5-backed search with confidence scoring and automatic decay for stale entries.

What you see here persists into your next session.

---

That's the core loop. For deeper coverage of each component, see [Core Concepts](core-concepts.md).
