---
paths:
  - "**/*"
---

# Use TeamCreate, Not Agent Tool

## Mandatory
- ALL multi-task implementation work MUST use TeamCreate to create a team, then spawn named teammates
- NEVER use the Agent tool directly for implementation tasks without a team
- The Agent tool without team_name is ONLY acceptable for quick read-only exploration (subagent_type=Explore)

## Why
- TeamCreate provides task tracking, teammate coordination, and structured progress
- Agent tool spawns anonymous fire-and-forget subagents with no coordination
- The user has explicitly and repeatedly demanded this

## Pattern
1. TeamCreate with descriptive name
2. TaskCreate for each piece of work
3. Agent tool WITH team_name and name parameters to spawn teammates
4. TaskUpdate to track progress
5. SendMessage for coordination
6. TeamDelete when done

## Task System
- ALL work items MUST be tracked with TaskCreate before starting
- TaskUpdate to in_progress when starting a task
- TaskUpdate to completed ONLY when genuinely done (TaskCompleted hook verifies this)
- TaskList to check progress and find next work
- Tasks trigger quality gates: TaskCompleted fires enforce-task-quality.sh and verify-task-done.sh
- Without tasks, quality gate hooks NEVER fire — this is why task usage is mandatory

## Git Workflow
- Commit after each completed task — never accumulate uncommitted work
- Use conventional commits: feat:, fix:, refactor:, chore:
- Stage specific files, not git add -A (blocked by hook)
- Push to remote regularly — local-only work is at risk
- Never end a session with uncommitted changes
- When spawning teammates that edit files in parallel: use `isolation: "worktree"` on Agent tool to give each agent an isolated git worktree. This prevents file conflicts between simultaneous agents.

## No Exceptions
- There are ZERO exceptions. ALL Agent tool calls go through TeamCreate.
- Explore, Plan, implementation, research — everything uses a team.
- This is because TaskCompleted/TeammateIdle hooks only fire within a team context, and those hooks enforce ALL quality gates.
- The enforce-team-usage.sh hook deterministically blocks any Agent call without a valid team.
