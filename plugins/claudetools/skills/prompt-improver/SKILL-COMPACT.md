# Prompt Improver (Compact)

> This is the compact version. For full creative workflow, invoke with `/prompt-improver build`

Transform rough user input into structured XML prompts and execute them. Three modes: execute (default), plan (review first), task (create persistent tasks).

## Modes

| Invocation | Behaviour |
|------------|-----------|
| `/prompt-improver <prompt>` | Generate XML, brief summary, execute immediately |
| `/prompt-improver plan <prompt>` | Generate XML, show full prompt, wait for user decision |
| `/prompt-improver task <prompt>` | Generate XML, create persistent tasks via task_create, do not execute |

## Workflow

1. **Triage**: If input is a file path, read it. If a URL, fetch it. Classify as trivial / already execution-ready / rough / mixed.
2. **Skip generation** if input is already well-structured XML or a detailed spec — go straight to execution or task creation.
3. **Summarise** conversation context (3-5 sentences) for the generation agent.
4. **Load references** (read and embed in agent prompt): `${CLAUDE_SKILL_DIR}/references/xml-template.md`, `prompting-principles.md`, `prompt-chaining.md`, `${CLAUDE_SKILL_DIR}/examples/before-after.md`
5. **Spawn generation agent** with context + references + raw input.
6. **Validate** generated prompt: `echo "<prompt>" | bash ${CLAUDE_SKILL_DIR}/scripts/validate-prompt.sh`

## Key Constraints

- The generation agent MUST NOT call task_create, execute the prompt, or modify the codebase.
- Match output size to input quality — a detailed 1700-line spec should not become a 200-line summary.
- Every task block needs verification commands, acceptance criteria, and file references.
- In execute mode: create a feature branch, run deterministic ops via Bash, verify per task, commit on pass.
- In task mode: create parent + subtasks with self-contained PRD content, then invoke `/claudetools:task-manager start`.

## Verification

- Generated prompt passes `validate-prompt.sh` with no FAIL errors.
- Execute mode: typecheck and test suite pass after implementation.
- Task mode: subtask count matches `<task>` block count in generated XML.

## Scripts

| Script | Use |
|--------|-----|
| `scripts/gather-context.sh .` | Detect tech stack and build/test/typecheck commands |
| `scripts/validate-prompt.sh` | Structural validation of generated XML prompt |

## Reference Files

All at `${CLAUDE_SKILL_DIR}/references/`: `xml-template.md`, `prompting-principles.md`, `prompt-chaining.md`. Examples at `${CLAUDE_SKILL_DIR}/examples/before-after.md`.
