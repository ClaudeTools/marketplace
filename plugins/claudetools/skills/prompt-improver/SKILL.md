---
name: prompt-improver
description: Transforms vague prompts into structured XML and executes them. Modes: execute (default), plan (review before running), task (create persistent tasks without executing). Use when the user says improve prompt, make this work better, prompt engineer, or structure a prompt.
argument-hint: [plan|task] [prompt-text or description of what to improve]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
metadata:
  author: Owen Innes
  version: 6.0.0
  category: prompt-engineering
  tags: [prompting, xml, claude-code, workflow]
---

# Prompt Improver

Transform rough user input into structured XML prompts and execute them directly.

## Modes

| Invocation | Mode | Behaviour |
|------------|------|-----------|
| `/prompt-improver <prompt>` | **Execute** (default) | Generate, brief summary, execute immediately |
| `/prompt-improver plan <prompt>` | **Plan** | Generate, show full XML, wait for user decision |
| `/prompt-improver task <prompt>` | **Task** | Generate, create persistent tasks via task_create, do not execute |

When the first word of $ARGUMENTS is `plan` or `task` (case-insensitive), activate that mode. Strip the mode word from the arguments before passing the rest as raw input.

## Execution model

Two phases:
1. **Generate** — Delegate prompt construction to a subagent (keeps main context clean)
2. **Execute or Review** — Follow the prompt directly, or present it for review

## Phase 1: Generate

### Step 1: Triage the input

Before doing anything, resolve and classify the input:

**Resolve**: If the input is a file path, read it. If it's a URL, fetch it. The resolved content is what you classify.

**Classify** the resolved content:
- **Trivial** (typo, rename, single-line fix): Ask: "This looks straightforward — should I just do it directly?"
- **Already execution-ready** (well-structured XML, detailed spec with code examples/schemas/verification criteria, comprehensive implementation guide, long structured prompt with clear requirements): **Skip the generation agent entirely.** The input is already good — go straight to Phase 2 using the content as-is. In task mode, go straight to task creation/decomposition.
- **Rough input** (vague description, bullet points, incomplete thoughts, missing context): This is where prompt-improver adds the most value. Proceed to Step 2 and the generation agent.
- **Mixed** (some sections detailed, others vague): Proceed to Step 2, but tell the generation agent to preserve detailed sections and enrich only the vague ones.

### Step 2: Summarise conversation context

Write 3-5 sentences of context for the generation agent:
- What the user has been building/fixing this session
- Key decisions or constraints discussed
- Current codebase state
- If first message: note "No prior conversation context."

### Step 3: Spawn the generation agent

Use the Agent tool to spawn a general-purpose agent with this prompt (fill in `{CONVERSATION_SUMMARY}`, `{RAW_INPUT}`, and `{MODE}` — one of `execute`, `plan`, or `task`):

---

You are a prompt engineering specialist. Transform a raw user request into a structured XML prompt for Claude Code execution.

**CRITICAL: You are a GENERATION agent only. Your job is to return a prompt. You MUST NOT:**
- Call task_create, task_update, or any task management tools
- Create tasks, todo items, or persistent state of any kind
- Execute the prompt you generate
- Make changes to the codebase

**CRITICAL: Match your output to the input quality.** Read the raw input (including file contents if a path is provided) and assess its quality before deciding your approach:
- **Comprehensive input** (detailed spec with code examples, schemas, verification criteria, implementation order): Preserve all detail. Wrap in XML structure without compressing or stripping content. A well-written 1700-line spec should produce a proportionally detailed prompt, not a 200-line summary.
- **Rough input** (vague description, bullet points, incomplete thoughts): This is where you add the most value — research the codebase, fill gaps, add concrete requirements, add verification criteria, add structure.
- **Mixed input** (some sections detailed, others vague): Preserve the detailed sections, enrich the vague ones.

The decision is yours based on reading the content — a `.md` file could be either a comprehensive spec or rough notes. Assess the content, not the file extension.

**Conversation context:**
{CONVERSATION_SUMMARY}

**Raw user request:**
{RAW_INPUT}

**Output mode:** {MODE}
If mode is `task`, you MUST include `<acceptance_criteria>`, `<file_references>`, `<out_of_scope>`, `<verification_commands>`, `<reference_patterns>`, and `<risk_level>` sections in every `<task>` block. These fields are required for autonomous task execution — see the "Task mode enrichment" section above.

**Step 1: Gather codebase context**
Run silently to detect tech stack and conventions:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/gather-context.sh .
```
Extract the TYPECHECK, TEST, and BUILD commands. Use these exact commands in verification blocks.

**Step 2: Read prompting references**
Read these files for the XML template, transformation rules, and examples:
- ${CLAUDE_SKILL_DIR}/references/xml-template.md
- ${CLAUDE_SKILL_DIR}/references/prompting-principles.md
- ${CLAUDE_SKILL_DIR}/references/prompt-chaining.md
- ${CLAUDE_SKILL_DIR}/examples/before-after.md

**Step 3: Classify the input**
Determine:
- Task type: Build, Fix, Refactor, Research, Configure, Document, Migrate, or Review
- Scope: Single file, multi-file, cross-cutting, or full feature
- What is ambiguous or implicit?
- Does this need phasing (>5 tasks or >80 lines)?

**Step 4: Reason through the approach**
Before building the prompt, think through:
- How to decompose the request into concrete, sequenced tasks
- What is deterministic vs what needs reasoning
- What verification criteria prove each task is correct
- Whether independent tasks can run in parallel

**Step 5: Build the improved prompt**
Apply all transformation rules from the prompting principles:
- Replace vague adjectives with concrete specifications
- Add testable verification to every task — active checks (run tests, re-read files, verify output)
- Include a `<check>` block with end-of-work review steps including requirement-by-requirement status
- Add `<approach>` blocks for non-trivial decisions (think before implementing, commit to a decision)
- Add `<examples>` blocks with `<reasoning>` for any decision-point or pattern-based task — decision boundary examples with reasoning are the most effective steering technique
- Add `<escape>` clause in `<execution>` (flag contradictions rather than working around them)
- Include research directives for non-trivial tasks
- Calibrate emphasis to severity: calm instructions for most rules, but full emphasis (CRITICAL/NEVER) for safety/security rules — the emphasis decision matrix in prompting-principles.md defines the thresholds
- Put data and context at the top, instructions at the end
- Write `<constraints>` that prevent likely failure modes for this specific task (not generic boilerplate)
- Reference existing code patterns where applicable
- Right-size the prompt for the task scope
- Use positive framing for outputs, negative framing for hard behavioural prohibitions — pair negatives with positive alternatives
- For autonomous agent prompts: include `<override_rules>` trust hierarchy, `<tool_routing>`, and `<risk_assessment>` blocks from the extended template
- For complex tasks: add `<known_failure_modes>` if empirical testing reveals recurring failures

For multi-task work, include a `<strategy>` in `<execution>` recommending sequential or parallel execution. Use teams (TeamCreate) when 3+ independent tasks benefit from parallel work. For simple or single tasks, work directly.

**Task mode enrichment:** When the caller indicates the output will be used for task creation (task mode), each `<task>` block in the generated XML MUST include these additional sections so that subtasks are self-contained for autonomous execution:
- `<acceptance_criteria>` — verb-led, measurable, pass/fail items (e.g. "Returns 404 when resource not found")
- `<file_references>` — with `<read>`, `<modify>`, and `<do_not_touch>` sub-elements listing exact paths
- `<out_of_scope>` — explicit exclusions to prevent scope creep
- `<verification_commands>` — exact shell commands an agent can run to prove the task is done (e.g. `npm test -- --grep "auth"`)
- `<reference_patterns>` — paths to existing code that should be followed as examples, with a note on what aspect to follow
- `<risk_level>` — low / medium / high

**Step 6: Validate**

**Part A — Run the validation script:**
```bash
echo "<the generated prompt>" | bash ${CLAUDE_SKILL_DIR}/scripts/validate-prompt.sh
```
Fix any FAIL errors and re-validate until PASS.

**Part B — AI quality review (reduced scope):**
The script handles structural checks. Review only:
- Does the prompt capture the user's intent?
- Are requirements complete and coherent?
- Are constraints reasonable?
- Is the prompt right-sized?

**Return only the final XML prompt. No explanation, no code fences, no commentary.**

---

## Phase 2: Execute or Review

### Execute mode (default)

1. **Brief plan**: Tell the user in 2-3 sentences what you're about to do. Do not show the XML.

2. **Branch**: Create a feature branch if not already on one.

3. **Deterministic first**: Run all deterministic operations directly via Bash — git, tests, typecheck, grep, sed. AI handles code generation, reasoning, and debugging only.

4. **Execute**: For multi-task work with 3+ independent tasks, use TeamCreate for parallel execution. For simpler work, execute directly. Match the execution approach to the task scope.

5. **Verify per task**: Run verification commands via Bash. Parse output deterministically (exit codes, grep matches). Commit with a conventional message if verification passes.

6. **Check your work** (mandatory final step):
   - Re-read every changed file for correctness
   - Run typecheck and test suite
   - Verify no regressions
   - Push the branch
   - Report: what was done, what was verified, any caveats

### Plan mode (`/prompt-improver plan ...`)

1. **Show the prompt** in an xml code fence.

2. **Summarise** (3-5 sentences): context pulled, assumptions made, ambiguities resolved, task count, recommended execution strategy.

3. **Offer options**:
   > **Ready to proceed?**
   > - **Execute** — run this prompt as-is
   > - **Revise** — tell me what to change
   > - **Edit** — paste back modified prompt
   > - **Discard** — cancel

4. **Handle response**:
   - **Execute**: Brief plan, then follow the prompt.
   - **Revise**: Re-spawn agent with original input + revision notes, present again.
   - **Edit**: Acknowledge changes, ask again.
   - **Discard**: Acknowledge and stop.

### Task mode (`/prompt-improver task ...`)

Create persistent tasks from the generated prompt instead of executing. This mode connects prompt-improver to the task management system.

1. **Run Phase 1 (Generate)** identically to execute/plan modes — same agent, same references, same validation.

2. **Create parent task**: Call the MCP `task_create` tool with:
   - `content`: the overall description from the user's input
   - `priority`: "high"
   - `tags`: ["prompt-improved"]
   - `metadata`: `{"generated_prompt": "<the full XML prompt>"}`

3. **Create subtasks**: For each `<task>` block in the generated XML prompt, call `task_create` with:
   - `parent_id`: the parent task's ID (returned from step 2)
   - `priority`: derive from position (first tasks get "high", later ones get "medium")
   - `tags`: ["prompt-improved", task-name-from-xml]
   - `dependencies`: map `depends-on` attributes to the corresponding subtask IDs (create tasks in order, track ID mapping)
   - `content`: structured as a **self-contained PRD** so an autonomous agent can execute with zero clarification:

     ```markdown
     ## [Task Title]

     ## Description
     [What this task does and why it matters in the context of the parent goal]

     ## Acceptance Criteria
     - [ ] [Verb-led, measurable, pass/fail criterion]
     - [ ] [Each criterion independently verifiable]

     ## File References
     - **Read:** [exact paths the agent needs to understand before starting]
     - **Modify:** [exact paths the agent will change]
     - **Do not touch:** [paths that must remain unchanged]

     ## Reference Patterns
     - Follow `[path]` for [aspect — e.g. naming conventions, error handling, test structure]

     ## Constraints
     - [Hard limits — e.g. no new dependencies, must be backwards compatible]

     ## Out of Scope
     - [Explicitly excluded items to prevent scope creep]

     ## Verification
     - `[exact shell command]` — [what it proves]
     - `[exact shell command]` — [what it proves]

     ## Risk Level
     [low / medium / high — with one-line justification]
     ```

     Every section is required. An executing agent must be able to complete this task from the content alone without re-reading the source spec.

   - `metadata`: structured data for programmatic access:
     ```json
     {
       "file_references": { "read": [...], "modify": [...], "do_not_touch": [...] },
       "acceptance_criteria": ["verb-led criterion 1", "..."],
       "out_of_scope": ["excluded item 1", "..."],
       "verification_commands": ["npm test -- --grep auth", "..."],
       "reference_patterns": [{ "path": "src/example.ts", "aspect": "error handling" }],
       "risk_level": "low|medium|high"
     }
     ```

4. **Parallel execution note**: When the task tree contains 3+ independent subtasks (no mutual dependencies), include a recommendation to use TeamCreate for parallel execution when the user starts the work. Add `"recommended_strategy": "parallel"` or `"sequential"` to the parent task's metadata.

5. **Present the task tree** to the user:
   ```
   Created task tree:
   - [task-parent-id] Overall description (high, prompt-improved)
     - [task-sub1] First subtask (high, depends on: none)
     - [task-sub2] Second subtask (medium, depends on: sub1)
     - [task-sub3] Third subtask (medium, depends on: sub1)
   ```

6. **Do not execute**. Tell the user: "Tasks created. Run `/claudetools:task-manager start` to begin execution."

## Edge cases

### Weak prompt returned
If the result is missing verification, too vague, or ignores the principles — re-spawn the agent with specific feedback.

### Prompt needs chaining
If the agent returns "Phase 1 of N":
- **Execute mode**: Execute Phase 1. Ask before proceeding to Phase 2.
- **Plan mode**: Show Phase 1. Note subsequent phases. Execute only after approval.

## Reference files

Read by the generation agent, not loaded into main context:
- XML template: [references/xml-template.md](references/xml-template.md)
- Prompting principles: [references/prompting-principles.md](references/prompting-principles.md)
- Prompt chaining: [references/prompt-chaining.md](references/prompt-chaining.md)
- Before/after examples: [examples/before-after.md](examples/before-after.md)
