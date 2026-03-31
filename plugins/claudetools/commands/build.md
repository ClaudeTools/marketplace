---
description: "Execute an implementation plan with TDD and subagent dispatch."
argument-hint: "[plan-file-path]"
---

This is a workflow command. Execute the plan task by task:
1. Read the plan file
2. For each task, use the `claudetools:tdd` skill (test first, implement, verify)
3. Dispatch subagents for independent tasks when possible
4. After each task: verify tests pass, commit
5. If no plan exists, tell the user: "No plan found. Run **/design** first to create one."
