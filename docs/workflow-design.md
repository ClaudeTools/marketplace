# Claudetools Workflow Design

> Make the right thing easy and the wrong thing hard.

---

## The Problem

Claudetools has 15 skills and 9 slash commands. Superpowers has 14 skills and 3 commands. A user looking at the claudetools command list sees:

```
/claude-code-guide  /code-review  /docs-manager  /field-review
/hook-inventory  /logs  /memory  /mesh  /session-dashboard
```

None of these suggest a workflow. They're a toolbox, not a process. The user has to know which tool to pick and when to pick it.

Superpowers' commands are:
```
/brainstorm → /write-plan → /execute-plan
```

Three commands, clear sequence, each leads to the next.

---

## The Solution: Workflow Commands

Replace the toolbox model with a workflow model. Keep specialized skills available, but add workflow commands that guide the process.

### Primary Workflow (new features, major changes)

```
/research  →  /design  →  /build  →  /review  →  /ship
```

Each command:
1. Handles its phase of the workflow
2. Tells the agent what comes next
3. Routes to the best available skill (claudetools or superpowers)

### Bug Fix Workflow

```
/debug  →  /build  →  /review  →  /ship
```

### Exploration Workflow

```
/explore  →  /research
```

### Maintenance Workflow

```
/health  →  /improve
```

---

## Command Mapping

| Workflow Command | What it does | Delegates to |
|-----------------|-------------|-------------|
| `/research` | Research external APIs, libraries, current docs before implementing | NEW research skill |
| `/design` | Brainstorm approaches → write plan → architecture check | superpowers:brainstorming → superpowers:writing-plans |
| `/build` | Execute plan with TDD, dispatch agents, track tasks | superpowers:subagent-driven-development or executing-plans |
| `/review` | Structured 4-pass code review | claudetools:code-review |
| `/ship` | Finish branch, merge/PR, update docs | superpowers:finishing-a-development-branch + docs-manager |
| `/debug` | Evidence-based debugging | claudetools:debugger |
| `/explore` | Navigate and understand codebase | claudetools:codebase-explorer |
| `/health` | Plugin health + session metrics | claudetools:session-dashboard + field-review |
| `/improve` | Self-improvement loop | claudetools:plugin-improver |

### Specialized Commands (keep as-is)

| Command | Use case |
|---------|----------|
| `/frontend` | Frontend/UI-specific design (rename from /frontend-design) |
| `/prompt` | Prompt engineering (rename from /prompt-improver) |
| `/memory` | Cross-session memory management |
| `/mesh` | Multi-agent coordination |
| `/logs` | Session log analysis |

### Retired Commands

| Old Command | Replaced by |
|-------------|------------|
| `/claude-code-guide` | Available as skill, not needed as command |
| `/docs-manager` | Folded into `/ship` workflow |
| `/field-review` | Folded into `/health` |
| `/hook-inventory` | Folded into `/health` |
| `/session-dashboard` | Folded into `/health` |

---

## Implementation

### New Skill: research

Proactive research before implementation. Replaces the reactive `research-backing` validator.

### New Skill: workflow

The conductor. Maps tasks to phases, enforces ordering, routes to skills.

### Updated Commands

Create workflow commands that delegate to the right skills. Each command file tells the agent to invoke the appropriate skill.

### Updated Skill Router

The intent classifier in `inject-prompt-context.sh` should route to workflow commands, not individual skills:

```
"build/create/implement" → /design (not straight to implementation)
"fix/debug/broken"       → /debug
"review/audit"           → /review
"deploy/ship/merge"      → /ship
"research/docs/API"      → /research
"explore/find/where"     → /explore
```
