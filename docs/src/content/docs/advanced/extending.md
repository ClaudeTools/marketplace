---
title: "Extending"
description: "Write custom hooks, validators, skills, and agents — hook exit codes, JSON block format, and how to compose new workflows."
---
How to write custom hooks, validators, skills, and agents.

## Custom Hooks

Hooks are shell scripts registered in `hooks.json`. Claude Code calls them at lifecycle events.

### Hook Exit Code Contract

| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| `0` | Allow / no opinion | Execution continues |
| `1` | Warning | Claude receives a `systemMessage` with your output |
| `2` | Block | Claude's tool call is rejected; your output is shown as the reason |

For `PreToolUse` hooks, blocks are emitted as JSON to stdout:

```bash
jq -n --arg reason "reason text" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
exit 0
```

Warnings are emitted as:

```bash
echo '{"systemMessage": "your warning text"}'
exit 0
```

### Writing a Validator

1. Create `plugin/scripts/validators/my-check.sh`
2. Source `lib/hook-input.sh` globals are already available when sourced by a dispatcher
3. Define a single check function:

```bash
#!/bin/bash
# Validator: my-check — brief description
# Globals used: INPUT, FILE_PATH
# Returns: 0 = clean, 1 = warn, 2 = block

check_my_condition() {
  # Use hook_get_content for file content, hook_get_field for JSON fields
  local content
  content=$(hook_get_content)

  if echo "$content" | grep -q "forbidden-pattern"; then
    echo "Found forbidden pattern in $FILE_PATH"
    return 1  # warn
  fi
  return 0
}
```

4. Source it in the appropriate gate dispatcher and call your function via `run_pretool_validator "my-check" check_my_condition`

### Adding to a Gate

Edit the gate dispatcher (`pre-edit-gate.sh`, `pre-bash-gate.sh`, etc.) to source and call your validator:

```bash
source "$SCRIPT_DIR/validators/my-check.sh"
# ... after existing validators
run_pretool_validator "my-check" check_my_condition
```

## Custom Skills

Skills live in `plugin/skills/<skill-name>/`. The minimum required file is `SKILL.md`.

### SKILL.md Frontmatter

```yaml
---
name: my-skill
description: One-line description shown in the skill picker and used by the agent router
argument-hint: [optional hint shown after /my-skill]
allowed-tools: Read, Bash, Grep, Glob
metadata:
  author: Your Name
  version: 1.0.0
  category: navigation
  tags: [tag1, tag2]
---
```

**Required fields:** `name`, `description`

**`allowed-tools`** — comma-separated list of Claude Code tools this skill is permitted to use. Omit to allow all tools.

The body of `SKILL.md` is the system prompt injected when the skill is invoked. Write it as instructions to Claude.

Skills are invoked with `/my-skill [arguments]` in the chat. The argument string is available as `$ARGUMENTS` in Bash commands within the skill.

### Adding Scripts

Place supporting scripts in `plugin/skills/<skill-name>/scripts/`. Reference them in the skill prompt:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/my-skill/scripts/helper.sh
```

## Custom Agents

Agents live in `plugin/agents/<agent-name>.md`.

### Agent Frontmatter

```yaml
---
name: my-agent
description: When to invoke description — used by the agent router to match user intent
model: sonnet
color: blue
tools: Glob, Grep, LS, Read, Edit, Write, Bash, WebFetch, WebSearch, TodoWrite
---
```

**`model`** — `opus`, `sonnet`, or `haiku`. Pipelines use `sonnet`; the architect agent uses `opus`.

**`color`** — display color in the agent UI: `green`, `blue`, `red`, `orange`, `cyan`, `purple`, `yellow`.

**`tools`** — complete allowlist. Read-only agents omit `Edit`, `Write`, `Bash`, `Agent`, `TeamCreate`, `TeamDelete`, `SendMessage`.

The body of the agent `.md` file is its system prompt.

### Read-Only vs Full Access

Read-only agents (architect, code-reviewer, security-pipeline, researcher, exploring-codebase) only have: `Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput`

Full-access agents additionally have: `Edit, Write, NotebookEdit, Bash, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet`

## Custom Rules

Rules are markdown files in `plugin/rules/`. They are injected as reference context. No special frontmatter is required — plain markdown.

```markdown
# My Rule

Description of the rule and when it applies.

**When to apply:** [conditions]

**What to do:** [action]
```

## The `claude-code-guide` Command

The `claude-code-guide` skill documents all available hooks, validators, skills, and agents. Run `/claude-code-guide` in the chat to get a live reference of the current plugin configuration. Use it when writing new extensions to check for naming conflicts or to understand the existing hook wiring.
