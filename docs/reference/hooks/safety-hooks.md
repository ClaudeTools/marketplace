---
title: Safety Hooks
parent: Hooks
grand_parent: Reference
nav_order: 1
---

# Safety Hooks

Hooks that enforce safety boundaries — stopping dangerous operations, protecting sensitive files, preventing harmful Bash commands, and blocking secret exposure.

---

## enforce-user-stop

**Event:** PreToolUse (all tools)
**Script:** `scripts/enforce-user-stop.sh`

Runs on every tool call. Checks if the user has issued a stop signal (e.g., typed "STOP" or "stop"). If detected, blocks all tool execution immediately.

This is the highest-priority hook — it runs before any other PreToolUse hook.

---

## guard-sensitive-files

**Event:** PreToolUse (Read, Edit, Write)
**Script:** `scripts/guard-sensitive-files.sh`

Blocks reads and writes to files containing secrets or credentials: `.env`, `*.pem`, `*.key`, `id_rsa`, `credentials.*`, and similar patterns.

Prevents accidental exposure of secrets when browsing or editing a project.

---

## pre-bash-gate / post-bash-gate

**Event:** PreToolUse / PostToolUse (Bash)
**Scripts:** `scripts/pre-bash-gate.sh`, `scripts/post-bash-gate.sh`

The pre-bash gate screens shell commands for dangerous patterns before execution:
- `rm -rf` on non-temp directories
- Destructive `git` operations (`reset --hard`, `force-push`)
- Commands that target config or credential files
- Commands that could exfiltrate data (`curl | sh`, pipe to remote)

The post-bash gate captures outcomes for failure pattern analysis.

---

## AI Safety Validators

**Event:** PreToolUse (Edit, Write, Bash)
**Script:** `scripts/enforce-memory-preferences.sh`

Checks that planned actions do not contradict stored memory preferences marked `ALWAYS` or `NEVER`. Runs before edits and Bash commands.

Also includes content validation (`scripts/validate-content.sh`, PostToolUse on Edit/Write) that scans file changes for:
- Stub implementations (`throw new Error("Not implemented")`)
- Placeholder content (`TODO`, `FIXME`, `lorem ipsum`)
- Disabled type safety (`@ts-ignore`, `as any`)

---

## auto-approve-safe

**Event:** PermissionRequest
**Script:** `scripts/auto-approve-safe.sh`

Automatically approves low-risk permission requests (e.g., reading files in the project directory) without prompting the user. Reduces friction for routine operations while leaving higher-risk requests for explicit approval.

---

## failure-pattern-detector / capture-failure

**Event:** PostToolUseFailure
**Scripts:** `scripts/failure-pattern-detector.sh`, `scripts/capture-failure.sh`

Runs after every tool failure. The detector identifies recurring failure patterns (e.g., Edit failing repeatedly on the same file) and escalates to a block if the pattern indicates a systemic issue. The capture script records failure data for telemetry and the improvement loop.
