# Skills Guide

How to build effective Claude Code skills — from directory layout to description optimization.

## Table of Contents

- [Skill anatomy](#skill-anatomy)
- [Frontmatter schema](#frontmatter-schema)
- [Resource architecture](#resource-architecture)
- [Writing the SKILL.md](#writing-the-skillmd)
- [Description optimization](#description-optimization)
- [Skill types](#skill-types)
- [Starter template](#starter-template)
- [Gotchas](#gotchas)
- [Verification checklist](#verification-checklist)

---

## Skill anatomy

A skill is a directory containing a required `SKILL.md` and optional resource subdirectories:

```
skill-name/
  SKILL.md                 (required — workflow, routing, gotchas)
  scripts/                 (deterministic logic: validation, transformation)
  references/              (domain knowledge loaded conditionally)
  assets/                  (output templates, example files, static resources)
```

The SKILL.md acts as a router. It contains decision logic and workflow steps, delegating execution to scripts, loading domain knowledge from references, and anchoring output format with asset templates.

### How skills load into context

Skills use a three-level progressive disclosure system:

1. **Metadata** (name + description) — always in context for all installed skills (~100 tokens each). This is how Claude decides whether to trigger the skill.
2. **SKILL.md body** — loaded when the skill triggers. Budget: under 500 lines / ~5000 tokens.
3. **Bundled resources** — loaded on demand when the SKILL.md instructs it.

Context cost implications:
- **Scripts execute without loading into context.** A 500-line validation script costs zero tokens. The agent only sees stdout/stderr. Scripts are the most efficient resource.
- **References load fully when read.** Keep each file focused (~2000-3000 tokens). The agent reads the whole file.
- **Assets are read or copied on demand.** Templates should be concise.

---

## Frontmatter schema

The YAML frontmatter block at the top of SKILL.md controls skill behavior:

```yaml
---
name: my-skill                    # Required. Lowercase, hyphens, numbers. Max 64 chars.
                                  # Must match the parent directory name.
description: >                    # Required. Max 1024 chars. Primary trigger mechanism.
  What the skill does and when to use it.
  Use when the user [trigger contexts].
argument-hint: "<subcommand>"     # Optional. Shown in slash-command help.
allowed-tools: Read, Bash, Grep   # Optional. Restricts which tools the skill can use.
model: opus                       # Optional. Forces a specific model for this skill.
metadata:                         # Optional. Arbitrary key-value pairs.
  author: Your Name
  version: 1.0.0
  category: development
  tags: [testing, automation]
---
```

**Fields in detail:**

| Field | Required | Notes |
|---|---|---|
| `name` | Yes | Must match directory name. Lowercase + hyphens + numbers only. |
| `description` | Yes | The entire burden of triggering rests on this field. See [Description optimization](#description-optimization). |
| `argument-hint` | No | Appears in `/skill-name` help text. Use angle brackets for required args, square brackets for optional. |
| `allowed-tools` | No | Comma-separated tool names. Omit to allow all tools. |
| `model` | No | Force `opus`, `sonnet`, or `haiku`. Omit for the session's default model. |
| `metadata` | No | Arbitrary YAML. Useful for author, version, category, tags. |

---

## Resource architecture

Before writing anything, decide what belongs where. The wrong placement wastes context tokens or reduces reliability.

### When to use each resource type

| Content type | Put it in... | Why |
|---|---|---|
| Workflow steps, decision logic, gotchas | SKILL.md | Always loaded — keeps the agent oriented |
| Validation, transformation, formatting | scripts/ | Zero context cost, deterministic, reliable |
| Domain knowledge per variant | references/ | Loaded only when the specific variant applies |
| Output structure, examples | assets/ | Anchors output format more reliably than prose |

### The scripting decision

Ask for every instruction: "Could a script do this more reliably?"

**Script it when:** the logic is deterministic, involves data transformation, requires validation, or runs the same way every time.

**Instruct it when:** the task requires judgment, creativity, or varies significantly based on context.

Signals that a script is needed:
- Instructions containing "check that...", "validate...", "verify..."
- Data transformation: "convert...", "parse...", "format as..."
- Batch processing: "for each item..."
- Calculations or comparisons
- If the agent reinvents similar logic across test runs — bundle it
- Precision matters (exact field mapping, arithmetic, pixel-perfect formatting)
- External tools or APIs with specific calling conventions
- Output could be large — scripts handle file I/O without context bloat

### Script design patterns

The most common and highest-value script type is a **validation script** — the agent generates output, the script checks it, the agent fixes issues. This generate-validate-fix loop is more reliable than instructions alone.

Other patterns:
- **Extraction scripts** — parse complex inputs (PDFs, forms, schemas) into structured JSON the agent can work with
- **Transformation scripts** — convert formats, clean data, normalise structures. More reliable than inline transformation for large datasets.
- **Generation scripts** — produce files in specific formats (charts, styled documents). The agent provides data; the script handles formatting.

### Script interface requirements

- **`--help` is the interface contract** — the agent reads it to learn invocation. Include: description, all flags, 2-3 usage examples, exit codes.
- **Structured I/O** — accept JSON in, produce JSON out. Send data to stdout, diagnostics to stderr.
- **Helpful errors** — say what went wrong + what was expected + suggestion to fix.
- **Idempotent operations** — "create if not exists" is safer than "create and fail on duplicate."
- **Declare dependencies inline** — PEP 723 for Python, npm specifiers for Node. Scripts should run with `uv run` or `npx` without separate install steps.

### Wiring resources into SKILL.md

Resources only work if SKILL.md tells the agent exactly when to use them:

```markdown
## Workflow

1. Identify the input type
2. Read the relevant reference:
   - If AWS: read `references/aws.md`
   - If GCP: read `references/gcp.md`
3. Process: `python scripts/transform.py --input <file>`
4. Validate: `python scripts/validate.py output.json`
5. If validation fails, fix issues and re-validate
```

Every resource has a specific trigger point. Generic instructions like "see references/ for details" are nearly useless — the agent does not know when to look or which file to read.

### Real examples from this plugin

The `field-review` skill uses scripts for metrics collection (`scripts/collect-metrics.sh`) and feedback submission (`scripts/submit-feedback.sh`). The SKILL.md tells the agent exactly when to run each script.

The `mesh` skill delegates all operations to a Node.js CLI (`agent-mesh/cli.js`) — the SKILL.md is purely a router that maps subcommands to CLI invocations.

The `prompt-improver` skill delegates prompt generation to a subagent to keep the main context clean, then validates the output structure.

---

## Writing the SKILL.md

### Core principles

1. **Explain WHY, not just WHAT.** Reasoning-based instructions outperform rigid directives. Instead of `ALWAYS validate output`, write: "Validate output because the agent misses formatting errors ~30% of the time without script-based checking."

2. **Match specificity to fragility.** Be prescriptive where operations are fragile or order matters. Give freedom where multiple approaches are valid.

3. **Provide defaults, not menus.** When multiple tools could work, pick one and mention alternatives briefly. The agent wastes tokens deliberating over equal options.

4. **Add what the agent lacks, omit what it knows.** Focus on project-specific conventions, non-obvious edge cases, and particular tool APIs. Skip general knowledge.

5. **Use imperative form.** "Run the validation script" not "The validation script should be run."

### Emphasis calibration

Match emphasis intensity to actual severity:

| Severity | Mechanism | Limit |
|---|---|---|
| Critical (safety, data loss) | CAPITALISED keywords + WHY | 3-5 per skill |
| High (workflow correctness) | Numbered steps + XML tags | As needed |
| Medium (quality) | Bold + examples | Moderate |
| Low (preferences) | Inline prose | Unlimited |

Overusing CAPITALISED keywords causes desensitization. If the agent follows an instruction 100% of the time in testing, the emphasis level is sufficient. If it follows it where it should not (overtriggering), reduce emphasis.

### Conditional reference loading

Use explicit conditions, not vague pointers:

```markdown
## Provider-specific setup

Read the relevant reference before proceeding:
- If the user targets AWS: read `references/aws.md`
- If the user targets GCP: read `references/gcp.md`
- If the provider is unclear, ask before reading.
```

### Gotchas section

The highest-value content in many skills. Include concrete, environment-specific facts that defy reasonable assumptions:

```markdown
## Gotchas

- The `users` table uses soft deletes — queries must include
  `WHERE deleted_at IS NULL` or results include deactivated accounts.
- The field is `user_id` in the DB, `uid` in auth, and `accountId`
  in billing. All three are the same value.
```

When the agent makes a mistake during testing, add the correction to gotchas.

### Verification checklist

Place at the END of the skill (positional weight — content at the end gets ~30% higher compliance). Include script-based checks wherever possible:

```markdown
## Verification checklist

Before finalising:
- [ ] Validation script passed: `python scripts/validate.py output/`
- [ ] Output matches template structure from `assets/output-template.md`
- [ ] No prohibited content in output
```

---

## Description optimization

The description field carries the entire burden of triggering. Claude reads all skill descriptions on every turn and decides which (if any) to invoke.

### Principles

1. **Use imperative phrasing.** "Use this skill when..." not "This skill does..." The agent is deciding whether to act.

2. **Focus on user intent, not implementation.** Describe what the user is trying to achieve.

3. **Be pushy.** Claude tends to under-trigger skills. Explicitly list contexts where the skill applies, including cases where the user does not name the domain directly.

4. **Include trigger keywords naturally.** Cover synonyms and indirect phrasings. Users say "spreadsheet", "data file", "table" when they mean CSV.

5. **Stay under 1024 characters.** Long enough to cover scope, short enough to avoid bloating context across many installed skills.

### Example — weak vs strong

Weak: "Process CSV files."

Strong: "Analyse CSV and tabular data files — compute summary statistics, add derived columns, generate charts, and clean messy data. Use when the user has a CSV, TSV, or Excel file and wants to explore, transform, or visualise data, even if they don't mention 'CSV' or 'analysis.'"

The strong version covers intent, capabilities, synonyms, and non-obvious triggers.

---

## Skill types

Different skill types need different writing strategies:

### Tool-orchestrating skills

Run scripts, call APIs, produce files. Need precise step sequences, script bundling, and validation loops.

Writing strategy: heavy on numbered workflow steps, validation scripts at every output point, structured I/O between steps. The SKILL.md is primarily a workflow router — most logic lives in scripts.

Example: `field-review` — collects metrics via script, structures a report, optionally submits telemetry.

### Knowledge-applying skills

Apply domain expertise to analysis, review, or writing. Need domain context in references, gotchas sections, and decision frameworks.

Writing strategy: conditional reference loading drives the workflow. SKILL.md acts as a router to the right reference file based on context. Gotchas section is the highest-value content — non-obvious facts prevent real mistakes.

Example: `claude-code-guide` (this skill) — routes to reference files based on what the user is building.

### Workflow-automating skills

Multi-step processes with conditional branches. Need clear decision trees, progressive disclosure, and state tracking.

Writing strategy: explicit decision trees with numbered branches. Progressive disclosure — load complexity only when needed. State tracking via scripts or task system. Delegation to subagents for independent subtasks.

Example: `prompt-improver` — branches on mode (execute/plan/task), delegates to subagent, validates output, then executes or presents.

---

## Starter template

Copy this skeleton when creating a new skill:

```markdown
---
name: your-skill-name
description: >
  What the skill does. Use when the user [trigger contexts],
  even if they don't explicitly mention [domain keywords].
argument-hint: "[subcommand] [args]"
---

# Skill Name

Brief overview of what this skill does and why it exists.

## Available scripts

- `scripts/validate.py` — Validates output. Run after generating output.

## Workflow

1. [First step] — [why this matters]
2. [Conditional step]: Read the relevant reference:
   - If [condition A]: read `references/variant-a.md`
   - If [condition B]: read `references/variant-b.md`
3. [Processing step]: `python scripts/process.py --input <file>`
4. Validate: `python scripts/validate.py output.md`
   If validation fails, fix issues and re-validate.

## Gotchas

- [Non-obvious fact that would cause errors]
- [Edge case the agent will get wrong without this]

## Verification checklist

Before finalising:
- [ ] Validation script passed
- [ ] Output matches expected structure
- [ ] [Domain-specific quality check]
```

---

## Gotchas

- **SKILL.md must be under 500 lines.** If approaching this limit, move detail to `references/` with conditional loading instructions. The SKILL.md is the most expensive resource — loaded on every invocation.
- **Name must match directory.** The `name` field in frontmatter must exactly match the parent directory name.
- **Generic reference pointers are useless.** "See references/ for details" tells the agent nothing. Specify the condition and the file: "If working with AWS, read `references/aws.md`."
- **Scripts need `--help`.** The agent reads `--help` output to learn how to call a script. Include description, flags, usage examples, and exit codes.
- **Declare script dependencies inline.** Use PEP 723 for Python or npm specifiers for Node so scripts run with `uv run` or `npx` without separate install steps.
- **Bold in the prompt produces bold in the output.** If you do not want the agent's output to contain bold text, avoid bold in the SKILL.md. This is prompt style contagion.
- **Examples beat instructions.** A single well-chosen input/output example often outperforms a paragraph of instructions for controlling output format and tone.
- **Allowed-tools restricts but does not expand.** Setting `allowed-tools` only limits which tools the skill can use. It cannot grant access to tools the agent does not already have.

---

## Verification checklist

Before considering a skill complete:

- [ ] `name` in frontmatter matches the directory name
- [ ] `description` is under 1024 characters and uses imperative phrasing
- [ ] SKILL.md is under 500 lines
- [ ] Every reference file has a specific conditional loading instruction in SKILL.md
- [ ] Scripts have `--help` with description, flags, examples, and exit codes
- [ ] Script dependencies are declared inline (PEP 723 / npm specifiers)
- [ ] Gotchas section exists with environment-specific, concrete corrections
- [ ] Verification checklist is placed at the END of the SKILL.md
- [ ] At least one validation mechanism exists (script, checklist, or self-check loop)
- [ ] Source files are in `plugin/skills/`, not `plugins/`
- [ ] Tested with 2-3 realistic user prompts

See `references/hooks-guide.md` for hook-related details if the skill interacts with hooks. See `references/agents-guide.md` if the skill spawns subagents.
