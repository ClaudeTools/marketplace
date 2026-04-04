---
name: task-manager
description: Extended task management with persistence, cross-session continuity, and validation. Use when the user says /task-manager, task status, manage tasks, restore tasks, or session handoff.
disable-model-invocation: true
argument-hint: [new|start|stop|status|restore|decompose|progress|handoff|validate]
allowed-tools: Read, Bash, Grep, Glob, Write, Edit, Agent, TeamCreate, TeamDelete, SendMessage
metadata:
  author: Owen Innes
  version: 1.0.0
  category: task-management
  tags: [tasks, persistence, session, handoff, validation]
---

# Managing Tasks

You are executing the `/task-manager` skill. This is a subcommand router for the extended task system. It provides persistent storage, cross-session continuity, and deterministic validation on top of the built-in TodoWrite tool.

Parse the first argument to select the subcommand. Default to `status` if no argument is given.

---

### new

Create a new task with enriched context. The raw input goes through a lightweight enrichment pipeline before becoming a task — so the resulting task is detailed enough for an agent to execute without further clarification.

1. **Parse** the remaining arguments as the raw input.

2. **Explore the codebase** using srcpilot:
   - Run `srcpilot map` to get the project overview (languages, structure, entry points, key exports)
   - For any file paths mentioned in the input, run `srcpilot overview "<path>"` and `srcpilot related "<path>"` to verify they exist and understand their structure
   - For any function/class names mentioned, run `srcpilot find "<name>"` to locate them
   - Store this context as `{CODEBASE_CONTEXT}` — it will be passed to the enrichment agent or used directly for triage

3. **Resolve and triage** the input:
   - If the input is a file path, read it. If it's a URL, fetch it. The resolved content is what you assess.
   - **Already detailed** (comprehensive spec, structured prompt with requirements/verification/approach, implementation guide with code examples): Skip the enrichment agent. However, still verify file references against `{CODEBASE_CONTEXT}` — replace any invented paths with real ones discovered from the srcpilot CLI. Go straight to step 5 (task creation).
   - **Needs enrichment** (vague, rough notes, missing context, incomplete): Proceed to step 4.

4. **Enrich** (only if triage says input needs it) — Read [references/enrichment-agent.md](references/enrichment-agent.md) to get the full agent prompt. Spawn a general-purpose Agent with that prompt, substituting `{RAW_INPUT}` with the original input and `{CODEBASE_CONTEXT}` with the context gathered in step 2.

5. **Create tasks** based on the enrichment output:

   **If single task (markdown block):**
   - Create one task using MCP `task_create` (preferred) or `TaskCreate`
   - `content`: The full enriched markdown block (not a summary)
   - `priority`: Infer from content — default `medium`, use `high` for urgency/blockers/critical fixes
   - `tags`: Extract from content — technology names, component names, task type
   - `metadata`: Extract structured fields from the markdown and store them for programmatic access:
     ```json
     {
       "source": "<original input>",
       "file_references": { "read": [...], "modify": [...], "do_not_touch": [...] },
       "acceptance_criteria": ["..."],
       "out_of_scope": ["..."],
       "verification_commands": [{ "command": "...", "proves": "..." }],
       "reference_patterns": ["..."],
       "risk_level": "low|medium|high"
     }
     ```

   **If decomposed (JSON with parent + subtasks):**
   - Create the parent task first with the parent's full content rendered as markdown
   - Create each subtask with `parent_id` set to the parent's task ID
   - Map `depends_on` indices to the created subtask IDs for `dependencies`
   - Each subtask's `content` is its full description/acceptance_criteria/constraints/verification — not a one-liner
   - Each subtask's `metadata` includes `file_references`, `acceptance_criteria`, `out_of_scope`, `verification_commands`, `reference_patterns`, and `risk_level` extracted from the JSON
   - Present the full task tree to the user

6. **Post-creation validation** (mandatory for decomposed tasks):
   - Read back all created subtasks
   - Verify each subtask has acceptance criteria (≥2 items), file references (≥1 path), and verification commands (≥1 command)
   - Check that verification/testing tasks have at least half the content length of the average implementation task — warn if any are significantly thinner
   - If the input mentioned N phases/steps/layers but only N-2 or fewer subtasks were created, warn about missing phases
   - Report any issues to the user before confirming

7. **Confirm** creation to the user: show task ID(s), summary, priority, tags, and dependency tree (if decomposed).

---

### start

Pick up the next pending task and execute it.

1. Call the MCP `task_query` tool with `{"status": "pending", "has_blocker": false, "format": "json"}`.
2. Sort results by priority (critical > high > medium > low), then by creation date (oldest first).
3. If no eligible tasks exist, tell the user: "No pending tasks available. Create tasks with `/task-manager new` or `/claudetools:prompt-improver task`."
4. Select the first task. Mark it as in_progress using `task_update` with `{"id": "<task-id>", "status": "in_progress"}`.
5. Display: task ID, content, priority, tags, and parent context (if any). If the task has `metadata.verification_commands`, show them so the user knows how completion will be verified.
6. **ALL task execution uses TeamCreate.** Create a team for the task, then spawn teammates to do the work:
   - Check if the task has subtasks by calling `task_query` with `{"parent_id": "<task-id>", "format": "json"}`.
   - **Subtasks exist, 2+ independent**: Use TeamCreate, spawn one teammate per independent subtask. Each teammate gets the full subtask content, file_references, constraints, and verification_commands from metadata. Execute independent subtasks in parallel. Once a dependency completes, launch the next wave of newly-unblocked subtasks as new teammates.
   - **Subtasks exist, all sequential**: Use TeamCreate, spawn one teammate for the first subtask. When it completes, spawn the next. Each teammate gets full context.
   - **No subtasks (single task)**: Use TeamCreate with a single teammate to execute the task. This keeps execution isolated and the main context clean.
7. Check if the task has `metadata.generated_prompt` (set by prompt-improver task mode). If yes, pass that prompt to the teammate to guide execution. If no, the teammate works from the task content description.
8. After all teammates complete, mark the task as completed using `task_update` and record files_touched. Clean up the team with TeamDelete.

---

### stop

Mark the current in-progress task as completed.

1. Call the MCP `task_query` tool with `{"status": "in_progress", "format": "json"}`.
2. If no tasks are in_progress, tell the user: "No task is currently in progress."
3. If multiple tasks are in_progress, list them and ask the user which to complete.
4. If exactly one task is in_progress, select it automatically.
5. Record files_touched: run `git diff --name-only HEAD~1` to detect recently changed files.
6. Mark the task as completed using `task_update` with `{"id": "<task-id>", "status": "completed", "files_touched": [<detected files>]}`.
7. Display: completed task summary, files touched, duration.
8. Show the next eligible pending task (if any) as a suggestion: "Next up: <task content> (<priority>)".

---

### status

Display current task state. This is also the default when no argument is given.

1. Run the report script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/task-manager/scripts/task-report.js" --format markdown
```
2. Present the markdown output to the user.
3. If the script exits non-zero or `.tasks/tasks.json` does not exist, tell the user: "No tasks found. Use `/task-manager new <description>` to create one."

---

### restore

Restore tasks from a previous session into the TodoWrite display. Critical for cross-session continuity.

1. Check if `.tasks/progress.md` exists. If yes, read it FIRST — it provides narrative context about where the previous session left off.
2. Run the sync script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/task-manager/scripts/sync-display.js"
```
3. Parse the JSON output. It contains an array of task objects with `content` and `status` fields.
4. Call `TodoWrite` with the restored task list to sync the display.
5. Report to the user:
   - Total tasks restored
   - Status counts (pending, in_progress, completed, blocked)
   - Last session context (from progress.md, if available)

---

### decompose

AI-assisted task decomposition. Argument: target task description or ID.

1. Read `.tasks/tasks.json` and match the target task by content string or task ID prefix.
2. If the MCP `task_decompose` tool is available, call it to get parent context and suggested breakdown.
3. Analyse the task in context:
   - What files are likely involved?
   - What are the dependencies and execution order?
   - Are there natural separation points?
4. Generate 3-7 subtasks. Prefer fewer, more substantial subtasks over many trivial ones.
5. Add each subtask via `TaskCreate` with `parent_id` set to the parent task's ID.
6. Update the parent task's status to `in_progress` if it was `pending`.
7. Present the decomposition tree to the user.

---

### progress

Show or update the progress narrative.

1. Check if `.tasks/progress.md` exists.
   - If yes, read and display its contents.
   - If no, tell the user: "No progress file yet. Run `/task-manager handoff` at the end of a session to generate one."
2. If the user says "update" or the file is stale (last modified more than 2 hours ago):
   - Read `.tasks/tasks.json` and `.tasks/history.jsonl`
   - Generate an updated session block following the template in `assets/progress-template.md`
   - Prepend the new block to `.tasks/progress.md` (newest session at top)

---

### handoff

Session end workflow. Run this before ending a session or when context compaction is imminent.

1. Read `.tasks/tasks.json` for current state.
2. Read `.tasks/history.jsonl` for transition history since the last handoff.
3. Generate a session summary with these sections:
   - **Completed**: Each completed task with implementation detail, not just the task name.
   - **In Progress**: Each in-progress task with current state and what remains.
   - **Blocked**: Each blocked task with the specific blocker.
   - **Key Decisions**: Decisions that would be expensive to re-deliberate in a future session.
   - **Next Steps**: Concrete, actionable items in priority order.
4. Prepend the new session block to `.tasks/progress.md` (newest at top). Create the file if it does not exist.
5. Suggest committing `.tasks/` to git:
```
Consider committing the task state:
  git add .tasks/ && git commit -m "chore: update task state"
```

---

### validate

Run deterministic validation on the task state.

1. Run the validation script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/task-manager/scripts/validate-tasks.js"
```
2. Report the results:
   - Number of tasks checked
   - Validation errors (if any): duplicate IDs, invalid status values, orphaned subtasks, broken dependencies
   - Validation warnings (if any): stale tasks, missing tags, empty descriptions
3. If all checks pass, confirm: "Task state is valid."

---

## Gotchas

- **TodoWrite has no ID field.** Tasks are matched by content string. If you rephrase a task description, the system treats it as a deletion of the old task plus creation of a new one. Keep descriptions stable.
- **Hook fires on every TodoWrite including restores.** This is by design — the hook is idempotent because it uses deterministic IDs. Restoring tasks does not create duplicate history entries. See [references/task-schema.md](references/task-schema.md) for ID generation details.
- **Hook must complete in <100ms.** The PostToolUse hook runs synchronously. It has zero npm dependencies and uses only Node.js built-ins to stay fast.
- **progress.md uses append-prepend ordering.** Newest session block goes at the top of the file, so the most recent context is always first.
- **.tasks/ belongs in version control.** The entire directory is designed to be committed. It contains only JSON, JSONL, and markdown — no binaries, no secrets.

---

## Conditional References

- Load [references/task-schema.md](references/task-schema.md) when working with tasks.json fields, debugging validation errors, or understanding the data model.
- Load [references/workflow-patterns.md](references/workflow-patterns.md) when handling complex multi-task workflows, decomposition strategies, or session handoff patterns.
- Load [references/setup-guide.md](references/setup-guide.md) when the persistence hook or MCP server is not configured, or when troubleshooting why tasks are not being saved.
- Load [references/enrichment-agent.md](references/enrichment-agent.md) when spawning the enrichment agent during `/task-manager new` (step 4).
