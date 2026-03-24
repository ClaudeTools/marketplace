---
title: "Process Hooks"
description: "Process Hooks — claudetools documentation."
---
Hooks that enforce workflow process — git discipline, task management, team coordination, and task completion quality gates.

---

## enforce-git-commits

**Event:** TeammateIdle
**Script:** `scripts/enforce-git-commits.sh`

Fires when a teammate goes idle. Checks whether the agent has uncommitted changes. If changes exist without a corresponding commit, the hook emits a warning to commit before ending the session or going idle.

Prevents accumulating uncommitted work across long sessions.

---

## enforce-team-usage

**Event:** PreToolUse (Agent)
**Script:** `scripts/enforce-team-usage.sh`

Blocks bare `Agent` tool calls when the TeamCreate tool is available. Enforces the rule: multi-task implementation work must use TeamCreate rather than spawning anonymous fire-and-forget subagents.

Ensures agent work is tracked, coordinated, and visible. Does not apply when `TeamCreate` is not in the available tools list.

---

## enforce-task-quality

**Event:** TeammateIdle
**Script:** `scripts/enforce-task-quality.sh`

Runs when a teammate goes idle. Checks whether tasks that were marked `in_progress` have been properly updated with status, files_touched, and outcome. Warns if tasks appear to have been abandoned without resolution.

---

## task-completion-gate

**Event:** TaskCompleted
**Script:** `scripts/task-completion-gate.sh`

Runs when a task is marked `completed`. Verifies the task actually meets its acceptance criteria by checking:
- Verification commands listed in the task ran successfully
- Files declared in `file_references.modify` were actually touched
- The task was not marked completed with zero tool calls

Blocks or warns when a task appears to be falsely completed.

---

## session-stop-dispatcher / session-end-dispatcher

**Event:** Stop / SessionEnd
**Scripts:** `scripts/session-stop-dispatcher.sh`, `scripts/session-end-dispatcher.sh`

Run at session end. Responsibilities:
- Check for uncommitted work and warn
- Run `mesh-lifecycle.sh deregister` to remove the agent from the active agents list
- Trigger `close-worktree-session.sh` for worktree cleanup
- Capture session outcomes for telemetry

---

## mesh-lifecycle

**Event:** SessionStart, SubagentStart, SubagentStop, SessionEnd, WorktreeCreate
**Script:** `scripts/mesh-lifecycle.sh`

Manages agent registration in the agent mesh:
- `register` — on session/subagent start and worktree creation
- `deregister` — on session/subagent stop and session end

Ensures the `/mesh status` command always shows an accurate picture of active agents.

---

## doc-stale-detector

**Event:** SessionStart
**Script:** `scripts/doc-stale-detector.sh`

Runs at session start. Scans documentation files for stale dates or outdated content based on recent git changes. Emits warnings for docs that reference changed files but have not been updated.
