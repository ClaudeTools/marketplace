---
paths:
  - "**/*"
---

# Agent Coordination

## When Teams Are Available

If the `TeamCreate` tool is available (agent teams feature is enabled):

- ALL multi-task implementation work MUST use TeamCreate to create a team, then spawn named teammates
- NEVER use the Agent tool directly for implementation tasks without a team
- The Agent tool without team_name is ONLY acceptable for quick read-only exploration (subagent_type=Explore or Plan)
- The enforce-team-usage.sh hook deterministically blocks bare Agent calls when teams are enabled

### Why
- TeamCreate provides task tracking, teammate coordination, and structured progress
- Agent tool without a team spawns anonymous fire-and-forget subagents with no coordination

### Pattern
1. TeamCreate with descriptive name
2. TaskCreate for each piece of work
3. Agent tool WITH team_name and name parameters to spawn teammates
4. TaskUpdate to track progress
5. SendMessage for coordination
6. TeamDelete when done

## When Teams Are NOT Available

If the `TeamCreate` tool is NOT listed in your available tools:

- You MAY use the Agent tool directly for implementation subagents
- Use parallel Agent calls for independent work — spawn multiple agents in a single response
- Name your agents with the `name` parameter for readability (e.g., name: "test-runner")
- Use `subagent_type` to pick the right agent for the job
- Use `isolation: "worktree"` when spawning agents that edit files in parallel
- Track work with TaskCreate / TaskUpdate even without a team
- PostToolUse quality hooks still run on all Agent completions

## Task System (Always Applies)
- ALL work items MUST be tracked with TaskCreate before starting
- TaskUpdate to in_progress when starting a task
- TaskUpdate to completed ONLY when genuinely done (TaskCompleted hook verifies this)
- TaskList to check progress and find next work
- Tasks trigger quality gates: TaskCompleted fires enforce-task-quality.sh and verify-task-done.sh
- Without tasks, quality gate hooks NEVER fire — this is why task usage is mandatory

## Git Workflow (Always Applies)
- Commit after each completed task — never accumulate uncommitted work
- Use conventional commits: feat:, fix:, refactor:, chore:
- Stage specific files, not git add -A (blocked by hook)
- Push to remote regularly — local-only work is at risk
- Never end a session with uncommitted changes
- When spawning teammates that edit files in parallel: use `isolation: "worktree"` on Agent tool to give each agent an isolated git worktree. This prevents file conflicts between simultaneous agents.

Use /task-manager to track progress across tasks and sessions.
