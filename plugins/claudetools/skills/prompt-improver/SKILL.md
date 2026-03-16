---
name: prompt-improver
description: Transforms vague or unstructured user prompts into best-in-class XML-structured prompts optimised for Claude Code execution, then executes them. Use this skill whenever the user asks to improve a prompt, make a prompt better, structure a prompt, rewrite something for Claude Code, prompt engineer a task, or clean up a prompt. Also trigger when a user pastes a rough task description and wants it turned into something Claude Code can execute well, or says things like make this work better, optimise this, or fix this prompt.
argument-hint: [plan] [prompt-text or description of what to improve]
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

When the first word of $ARGUMENTS is `plan` (case-insensitive), activate Plan mode. Strip `plan` from the arguments before passing the rest as raw input.

## Execution model

Two phases:
1. **Generate** — Delegate prompt construction to a subagent (keeps main context clean)
2. **Execute or Review** — Follow the prompt directly, or present it for review

## Phase 1: Generate

### Step 1: Triage the input

Before doing anything, classify:
- Trivial change (typo, rename, single-line fix)? Ask: "This looks straightforward — should I just do it directly?"
- Already well-structured XML? Ask: "This is already well-structured — execute as-is, or run improvement?"

### Step 2: Summarise conversation context

Write 3-5 sentences of context for the generation agent:
- What the user has been building/fixing this session
- Key decisions or constraints discussed
- Current codebase state
- If first message: note "No prior conversation context."

### Step 3: Spawn the generation agent

Use the Agent tool to spawn a general-purpose agent with this prompt (fill in `{CONVERSATION_SUMMARY}` and `{RAW_INPUT}`):

---

You are a prompt engineering specialist. Transform a raw user request into a structured XML prompt for Claude Code execution.

**Conversation context:**
{CONVERSATION_SUMMARY}

**Raw user request:**
{RAW_INPUT}

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
- Include a `<check>` block with end-of-work review steps
- Add `<approach>` blocks for non-trivial decisions (think before implementing, commit to a decision)
- Add `<examples>` blocks for any pattern-based task (input/output pairs)
- Add `<escape>` clause in `<execution>` (flag contradictions rather than working around them)
- Include research directives for non-trivial tasks
- Use calm, direct language — no aggressive markers (avoid MUST, NEVER, CRITICAL, non-negotiable)
- Put data and context at the top, instructions at the end
- Write `<constraints>` that prevent likely failure modes for this specific task (not generic boilerplate)
- Reference existing code patterns where applicable
- Right-size the prompt for the task scope
- Use positive framing; state what to do, not what not to do

For multi-task work, include a `<strategy>` in `<execution>` recommending sequential or parallel execution. Use teams (TeamCreate) when 3+ independent tasks benefit from parallel work. For simple or single tasks, work directly.

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
