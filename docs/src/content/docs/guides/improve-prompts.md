---
title: "Improve Prompts"
description: "Improve Prompts — claudetools documentation."
---

Use `/improving-prompts` to turn a rough request into a structured XML prompt. Three modes: run it immediately, review it first, or convert it into a tracked task tree.

## Execute mode (default)

> "add dark mode support to the settings page"

Claude structures the request, shows you a brief plan, then implements without waiting:

:::note[Behind the scenes]
A generation agent is spawned in a sub-context. It reads 4 reference files (XML template, prompting principles, chaining patterns, before/after examples), runs `codebase-pilot map` to find real file paths, then produces a validated XML prompt. `validate-prompt.sh` checks structure — failures are auto-corrected. The main conversation agent then executes the prompt directly.
:::

```
Improving prompt and gathering codebase context...

Plan (3 steps):
  1. Add `theme` field to user preferences schema and settings API
  2. Implement dark/light CSS variables in globals.css, toggle in settings UI
  3. Persist preference to localStorage + user profile; apply on load

Executing...

  ✓ src/db/migrations/018_user_prefs.ts — added `theme` column
  ✓ src/api/settings.ts — GET/PATCH theme preference
  ✓ src/styles/globals.css — dark mode CSS variable overrides
  ✓ src/components/Settings/ThemeToggle.tsx — created
  ✓ src/hooks/useTheme.ts — reads preference, applies class to <html>
  ✓ src/app/layout.tsx — ThemeToggle added to settings section

Branch: feat/dark-mode-settings
Commit: feat: add dark mode support to settings page
```

Use execute mode when the request is focused and you are comfortable with Claude proceeding without review.

---

## Plan mode

> "/improving-prompts plan refactor the authentication middleware to support OAuth2"

Claude generates the structured prompt and presents it before doing anything:

:::note[Behind the scenes]
Same generation agent runs as in execute mode, but the result is printed to the conversation instead of being executed. Claude also summarises what assumptions were baked in (e.g., existing auth strategy, JWT vs session detection).
:::

```
Generated prompt (OAuth2 middleware refactor):

<task>
  <context>
    Current auth: JWT via src/middleware/auth.ts (handleAuth, requireRole)
    Session store: none — stateless JWT only
    Existing token validation: src/services/auth.ts:verifyToken
  </context>
  <objective>
    Extend handleAuth to accept OAuth2 Bearer tokens from external providers
    alongside existing JWTs. Do not break existing JWT flow.
  </objective>
  <steps>
    <step>Add OAuth2 provider config to src/config/auth.ts</step>
    <step>Extend verifyToken() to detect and validate OAuth2 tokens</step>
    <step>Update handleAuth middleware to call new verifyToken branch</step>
    <step>Add integration tests for both token paths</step>
  </steps>
  <constraints>
    Existing JWT auth must continue to work without changes for callers.
    No new dependencies — use node:crypto for token verification.
  </constraints>
</task>

Assumptions made:
  - Provider uses RS256 signed tokens
  - JWKS endpoint URL will be added to environment config
  - No session storage required (stateless verification)

What would you like to do?
  Execute — run this prompt as-is
  Revise  — tell me what to change
  Edit    — paste back a modified prompt
  Discard — cancel
```

You say "Execute" and Claude follows the structured plan exactly.

Use plan mode for anything that touches multiple files, involves an architectural decision, or where you want to verify assumptions before implementation starts.

---

## Task mode

> "/improving-prompts task build a real-time notification system with WebSocket support"

Claude generates the XML prompt, then converts it into a persistent task tree instead of executing:

:::note[Behind the scenes]
After the generation agent produces the prompt, Claude calls `task_create` for each `<step>` block in the XML, setting acceptance criteria, file references, and verification commands from the prompt's metadata. The parent task links to the original structured prompt.
:::

```
Generated prompt and created task tree:

[task-f2a9c1d0] Build real-time notification system (high)
  [task-a3b4c5d6] WebSocket server setup — src/ws/server.ts (high)
    Acceptance: WS server starts on same port, handles connect/disconnect
    Verify: curl --include --no-buffer -H "Upgrade: websocket" ...
  [task-b5c6d7e8] Notification event emitter — src/services/notifications.ts (high)
    Acceptance: emitToUser(userId, event) reaches all open connections
    Depends on: a3b4c5d6
  [task-c7d8e9f0] Client hook — src/hooks/useNotifications.ts (medium)
    Acceptance: hook reconnects on disconnect, exposes notifications[]
    Depends on: b5c6d7e8
  [task-d9e0f1a2] Notification bell UI — src/components/NotificationBell.tsx (medium)
    Acceptance: badge shows unread count, clears on open
    Depends on: c7d8e9f0
  [task-e1f2a3b4] Integration tests (medium)
    Acceptance: tests cover connect, message delivery, reconnect
    Depends on: b5c6d7e8

Tasks created. Start with task-a3b4c5d6, or say "start the notification system" to begin.
```

Use task mode for multi-session projects, backlog items you want to schedule, or work you want a separate agent to pick up.

---

:::tip[When to use what]
- **Clear task, just do it**: Skip `/improving-prompts` entirely — just tell Claude what you want
- **Vague idea, want structure**: Use execute mode — it structures the request and runs it immediately
- **Complex task, want to review the approach first**: Use plan mode — see the full plan and assumptions before anything is touched
- **Multi-session project, want persistent tracking**: Use task mode — creates a task tree you can come back to across sessions
:::

## Tips

- Use **execute mode** for single-concern requests: add a field, fix a bug, change a behaviour
- Use **plan mode** for refactors that touch multiple files or introduce a new architectural pattern
- Use **task mode** when the work spans multiple sessions or should be picked up by a separate agent
- If the generated prompt looks wrong in plan mode, say "Revise — add X constraint" — the generation agent re-runs with your notes
- The generation agent uses codebase-pilot to find real file paths — the output will never contain invented paths

## Related

- [Manage Tasks](manage-tasks.md) — task mode connects prompt-improver to the task system
- [Build a Feature](build-a-feature.md) — feature-pipeline uses improving-prompts internally for the plan step
- [Reference: improving-prompts skill](../reference/skills.md)
