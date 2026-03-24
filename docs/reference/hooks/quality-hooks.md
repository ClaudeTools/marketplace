---
title: Quality Hooks
parent: Hooks
grand_parent: Reference
nav_order: 2
---

# Quality Hooks

Hooks that enforce edit quality — preventing blind edits, catching stubs, limiting edit frequency, and validating content after writes.

---

## validate-content

**Event:** PostToolUse (Edit, Write)
**Script:** `scripts/validate-content.sh`

Scans every file write for quality violations:
- Stub implementations (`throw new Error('Not implemented')`, empty function bodies)
- Placeholder text (`TODO`, `FIXME`, `lorem ipsum`, `Example Item 1`)
- Type safety bypasses (`@ts-ignore`, `as any`, `eslint-disable`)
- Missing error handling in catch blocks

Warnings are emitted for each violation. Critical violations block the tool call.

---

## edit-frequency-guard

**Event:** PostToolUse (Edit, Write)
**Script:** `scripts/edit-frequency-guard.sh`

Tracks how many times each file has been edited in a session. When a file exceeds the churn threshold (default: 3 edits), the guard warns that the agent may be trial-and-erroring instead of planning before editing.

High churn is a signal that the agent did not understand the code before making changes.

---

## blind-edit protection (pre-edit-gate)

**Event:** PreToolUse (Edit, Write)
**Script:** `scripts/pre-edit-gate.sh`

Checks whether the file being edited has been read in the current session. If not, the edit is blocked with the message: "Read the file before editing."

This prevents the most common agent quality failure: editing code that has not been understood.

---

## enforce-read-efficiency

**Event:** PreToolUse (Read, Edit, Write)
**Script:** `scripts/enforce-read-efficiency.sh`

Blocks re-reading a file that is already fully in context (unchanged since last read). Forces the agent to use `offset`/`limit` for large files rather than re-reading from the beginning.

Reduces token waste from redundant file reads.

---

## post-agent-gate

**Event:** PostToolUse (Agent)
**Script:** `scripts/post-agent-gate.sh`

Runs after every agent/subagent completion. Verifies that the subagent completed its stated task by checking task state and output. Emits a warning if the subagent reported "done" without verifiable evidence.

---

## verify-subagent-independently

**Event:** SubagentStop
**Script:** `scripts/verify-subagent-independently.sh`

Runs when a subagent stops. Independently verifies the subagent's claimed outcomes (e.g., runs typecheck, checks file existence) rather than trusting the subagent's self-report.
