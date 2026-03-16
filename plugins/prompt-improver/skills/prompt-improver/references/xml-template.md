# XML Template Structure

The canonical template for improved prompts. Not every section is required — use judgment about what the task needs. Data and context go at the top, instructions and queries at the end.

## Full template

```xml
<!-- DATA FIRST: context and reference material at the top -->
<context>
  <project>{tech stack, framework, key libraries}</project>
  <scope>{what part of the codebase this touches}</scope>
  <conventions>{relevant patterns from CLAUDE.md or codebase inspection}</conventions>
  <!-- For fix/refactor tasks -->
  <current-behavior>{what happens now}</current-behavior>
  <desired-behavior>{what should happen}</desired-behavior>
  <error>{verbatim error if available}</error>
</context>

<!-- Reference material using document structure -->
<documents>
  <document index="1">
    <source>{file path or URL}</source>
    <document_content>{content to reference}</document_content>
  </document>
</documents>

<!-- Research directive -->
<research>
  Search before implementing:
  - {specific docs/APIs to look up}
  Explore the codebase:
  - {files/patterns to read}
</research>

<!-- Tasks with think-then-implement pattern -->
<task id="1" name="{kebab-case}">
  <description>{what this accomplishes}</description>

  <requirements>
    <group name="{category}">
      - {specific, testable requirement}
    </group>
  </requirements>

  <!-- Few-shot examples: the most effective steering tool -->
  <examples>
    <example>
      <input>{sample input}</input>
      <output>{expected output}</output>
    </example>
  </examples>

  <!-- References to existing patterns -->
  <references>
    - Follow the pattern in `{file path}`
  </references>

  <!-- Think-before-acting directive -->
  <approach>
    Before implementing, reason through:
    - {specific decision or design question}
    - {criteria for evaluation}
    Select an approach and commit to it.
  </approach>

  <!-- Deterministic verification -->
  <verification>
    - Run `{command}` and confirm {expected output}
    - grep {file} for {pattern} — confirm match
  </verification>
</task>

<task id="2" name="{next-task}" depends-on="1">
  {Same structure. Use depends-on when sequencing matters.}
</task>

<!-- Global execution guidance -->
<execution>
  <strategy>{sequential / parallel / phased}</strategy>

  <constraints>
    - {task-specific constraint that prevents a likely failure mode}
    - {another constraint specific to this task's risks}
  </constraints>

  <out-of-scope>
    - {what NOT to do}
  </out-of-scope>

  <!-- Escape clause — prevents hallucinated workarounds -->
  <escape>
    If any requirement seems contradictory, infeasible, or would degrade
    existing functionality — flag it and ask rather than working around it.
  </escape>
</execution>

<!-- Self-check: reiterate verification at end -->
<check>
  Before reporting completion:
  - Re-read every changed file — verify no placeholders, empty functions, or type escapes
  - Run {typecheck command}
  - Run {test command}
  - Compare each original requirement against actual implementation
  - Report status for each requirement: done / partial / skipped
</check>
```

## Minimal template (for simple tasks)

```xml
<context>
  <project>{tech stack}</project>
</context>

<task>
  <description>{what to do}</description>
  <requirements>
    - {specific requirement}
  </requirements>
  <verification>
    - {how to check it worked}
  </verification>
</task>

<check>
  - Re-read changed files — confirm no placeholders
  - Run {typecheck command}
</check>
```

## Tag reference

| Tag | Purpose | Required |
|-----|---------|----------|
| `<context>` | Project info, tech stack, conventions | Yes |
| `<current-behavior>` | What happens now (fix/refactor) | For fix/refactor tasks |
| `<desired-behavior>` | What should happen (fix/refactor) | For fix/refactor tasks |
| `<error>` | Verbatim error message | When error is available |
| `<documents>` | Reference material in document structure | When referencing external content |
| `<research>` | Online search and codebase exploration | Default for non-trivial tasks |
| `<task>` | Single unit of work | Yes (at least one) |
| `<description>` | What the task accomplishes | Yes |
| `<requirements>` | Specific, testable specs | Yes |
| `<examples>` | Input/output pairs for pattern-based tasks | Default for any pattern task |
| `<references>` | Existing code to follow | When patterns exist |
| `<approach>` | Think-before-acting reasoning | Default for non-trivial tasks |
| `<verification>` | Deterministic checks — commands to run | Yes |
| `<execution>` | Global approach and constraints | For multi-task prompts |
| `<constraints>` | Task-specific guardrails against likely failure modes | When there are task-specific risks |
| `<out-of-scope>` | What NOT to do | When scope creep is likely |
| `<escape>` | Permission to flag contradictions | Yes — always in execution |
| `<check>` | End-of-work review | Yes — always include |

## Tag usage principles

- Tags separate concerns — don't mix instructions with context with verification
- Tags should be self-descriptive — `<responsive-layout>` not `<part-a>`
- Nest when there's hierarchy — `<requirements>` > `<group name="ui">` > items
- 3 levels max nesting. If deeper, flatten or split into tasks
- Use attributes for metadata — `id`, `name`, `depends-on`
- Verification contains only runnable commands with checkable outputs
- Data and context go at the top, instructions at the end
- Constraints address task-specific failure modes, not generic quality rules
- Generic quality rules (no stubs, run tests, re-read files) belong in verification and check blocks
