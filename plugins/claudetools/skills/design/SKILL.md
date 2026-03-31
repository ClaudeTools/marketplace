---
name: design
description: >
  Full design phase — discover the problem, research dependencies, architect a
  solution, and write the implementation plan. Use before building anything
  non-trivial. This is the first command in the /design → /build → /ship workflow.
argument-hint: "[what to build or change]"
allowed-tools: Read, Glob, Grep, Bash, WebSearch, WebFetch, Write, AskUserQuestion, Agent
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [design, discovery, architecture, planning, workflow]
---

# /design — Discover, Architect, Plan

> HARD GATE: Do NOT write implementation code until the user has approved the design
> AND the plan is written. This applies to EVERY task regardless of perceived simplicity.

## Why This Gate Exists

| Rationalization | Reality |
|----------------|---------|
| "This is too simple to need a design" | Simple tasks with unexamined assumptions cause the most wasted work |
| "I already know how to do this" | You know how to do it in your training data. This codebase may differ. |
| "Let me just start coding and refactor later" | Refactoring code you shouldn't have written costs 3x more than designing first |
| "The user seems impatient" | A 2-minute design conversation saves 20 minutes of wrong-direction work |

## The Process

### Phase 1: Discover

Understand the problem before solving it.

1. **Explore the codebase** using codebase-pilot:
   ```bash
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<relevant-name>"
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<entry-point>"
   ```

2. **Check memory** for past decisions about this area:
   - Read `$HOME/.claude/projects/*/memory/MEMORY.md` for relevant entries
   - "Last time you worked on auth, you chose JWT because..."

### Check episodic memory

Before proposing approaches, check what this project has done before:

```bash
# Search memory for past decisions in this area
cat $HOME/.claude/projects/*/memory/MEMORY.md 2>/dev/null | grep -i "[relevant-topic]"
```

Past decisions to look for:
- Architecture choices ("chose X over Y because...")
- User preferences ("prefers small PRs", "no mocks in tests")
- Known gotchas ("the auth module requires X")

If relevant memories exist, reference them in your proposal: "Last time you worked on auth,
you chose JWT because of the stateless requirement. Same approach here?"

3. **Research external dependencies** (if task touches external APIs/libraries):
   - Use WebSearch + WebFetch to find current documentation
   - Verify API endpoints, SDK versions, auth methods
   - Skip if task is purely internal

4. **Ask clarifying questions** — one at a time via AskUserQuestion:
   - What problem does this solve? (if not obvious)
   - What constraints exist? (performance, compatibility, etc.)
   - What does success look like?

### Visual Companion (optional)

For tasks involving visual decisions (UI layouts, architecture diagrams, design comparisons), offer the browser companion:

> "Some of what we're designing might be easier to show visually. I can display mockups, diagrams, and comparisons in your browser. Want to try it?"

If accepted:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/start-server.sh --project-dir "$PWD"
```

Save the returned `screen_dir` and `state_dir`. Then for visual questions:

1. Write HTML fragments to `screen_dir/` (unique filenames: `layout.html`, `layout-v2.html`)
2. Tell the user the URL and what's on screen
3. On next turn, read `state_dir/events` for click selections (JSONL)
4. Use terminal for text questions, browser for visual questions

Available CSS classes: `.options`, `.option`, `.cards`, `.card`, `.mockup`, `.split`, `.pros-cons`

When returning to terminal questions, push a waiting screen:
```html
<div style="display:flex;align-items:center;justify-content:center;min-height:60vh">
  <p class="subtitle">Continuing in terminal...</p>
</div>
```

### Phase 2: Architect

Present 2-3 approaches with tradeoffs.

Use AskUserQuestion with preview panels to show each approach:

```
AskUserQuestion:
  question: "Which approach for [feature]?"
  options:
    - label: "Approach A: [name]"
      description: "[1-sentence tradeoff]"
      preview: |
        Architecture:
        [component diagram or code structure]

        Pros: [key advantage]
        Cons: [key disadvantage]
        Files: [N files changed]
    - label: "Approach B: [name]"
      ...
```

Lead with your recommendation. Explain why in 1 sentence.

### Example: Presenting approaches

The preview content should be concrete enough for the user to evaluate — not just labels.
Here is a fully worked example:

```
AskUserQuestion:
  question: "Which authentication approach for the API?"
  options:
    - label: "JWT Tokens"
      description: "Stateless, scalable, but requires token refresh logic"
      preview: |
        Architecture:
          Client → API Gateway → JWT Verify → Handler

        Pros: No session storage, horizontal scaling
        Cons: Token revocation is complex, larger payload
        Files: 3 new (middleware, token service, config)

    - label: "Session Cookies"
      description: "Simple, well-understood, requires session store"
      preview: |
        Architecture:
          Client → API Gateway → Session Lookup → Handler

        Pros: Simple revocation, small payload, httpOnly secure
        Cons: Requires Redis/DB for sessions, stateful
        Files: 2 new (middleware, session store)
```

Always lead with your recommendation and explain why in 1 sentence before presenting
the options. Example: "I recommend JWT Tokens — you already have a stateless architecture
and adding Redis for sessions would be a new dependency."

### Phase 3: Plan

After the user approves an approach, write the implementation plan:

1. **Map files** — use `related-files` and `file-overview` to list every file to create/modify
2. **Write tasks** — each task is one self-contained change:
   - Exact file paths
   - Complete code in every step
   - Test-first: failing test → implementation → verify → commit
   - No placeholders (never write "TBD", "add appropriate handling", "similar to Task N")
3. **Self-review** — check for: spec coverage, placeholder scan, type consistency
4. **Save** to `docs/plans/YYYY-MM-DD-<name>.md`

### Plan self-review

Before presenting the plan to the user, run this checklist:

1. **Spec coverage** — every requirement the user stated maps to at least one task.
   Scan: does each feature from Phase 1 appear somewhere in the task list?
2. **Placeholder scan** — search the plan text for "TBD", "add appropriate handling",
   "similar to Task N", "TODO", "left as exercise". If found, expand them inline now.
3. **Type consistency** — if a function or type is named X in Task 2, it must still be
   named X in Task 5. Inconsistent names mean the plan was written in pieces and not
   reviewed end-to-end.
4. **File completeness** — every task lists exact file paths. No task says "update the
   relevant files" without naming them.

Fix any issues found before presenting. The user should never have to point out a
placeholder in the plan — catch them yourself.

### Phase 4: Handoff

Present the plan summary and ask:

```
AskUserQuestion:
  question: "Plan ready — N tasks, M files. Start building?"
  options:
    - label: "Build it"
      description: "Execute the plan task-by-task with TDD"
    - label: "Review plan first"
      description: "Show the full plan for review before building"
    - label: "Adjust"
      description: "I want to change something in the design"
```

If "Build it" → tell the user: "Starting build phase. **Next: /build**"

## Safety Net

If /design is followed correctly, these validators should never fire:
- `task-scope.sh` — scope is defined by the plan's acceptance criteria
- `unasked-deps.sh` — dependencies are identified in the discovery phase
- `unasked-restructure.sh` — structural changes are in the plan
- `research-backing.sh` — external APIs were researched in discovery
