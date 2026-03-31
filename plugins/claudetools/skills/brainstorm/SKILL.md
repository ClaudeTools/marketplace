---
name: brainstorm
description: >
  Explore user intent, requirements, and design before implementation. Ensures
  you understand what to build and why before touching code. Use before any
  non-trivial feature, refactor, or architectural change.
argument-hint: "[feature or task description]"
allowed-tools: Read, Glob, Grep, Bash, WebSearch, WebFetch, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [design, brainstorming, requirements, planning]
---

# Brainstorm Before Building

> HARD GATE: Do NOT write implementation code, scaffold projects, or create files
> until you have presented a design and the user has approved it. This applies
> regardless of how simple the task seems.

## The Process

### Step 1: Understand the real problem

Ask yourself — not the user — these questions:
- What specific problem does this solve?
- Who experiences this problem and when?
- What does success look like?

If you can't answer all three, ask the user for clarification using AskUserQuestion.

### Step 2: Explore the codebase

Before proposing any design, understand what exists:
- What patterns does the codebase already use?
- What files will be affected?
- Are there existing utilities or abstractions to reuse?

Use codebase-explorer tools: `find-symbol`, `related-files`, `file-overview`.

### Step 3: Consider approaches

Identify 2-3 approaches. For each:
- What are the tradeoffs?
- What does it couple to?
- What becomes harder to change later?
- What's the simplest version that solves the real problem?

### Step 4: Present the design

Present your recommended approach to the user with:
- **What** you're building (1-2 sentences)
- **How** it works (architecture in 3-5 bullets)
- **Files** that will be created or modified
- **Why** this approach over alternatives (1 sentence)

### Step 5: Get approval

Wait for explicit user approval before proceeding.

After approval, tell the user: "Design approved. **Next: /plan** to create the implementation plan."

## When to Skip

Only skip brainstorming for:
- Single-line fixes (typos, obvious bugs)
- Changes where the user gave very specific, detailed instructions
- Pure research/exploration tasks
