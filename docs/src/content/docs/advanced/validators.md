---
title: "Validators"
description: "Validators — claudetools documentation."
---
26 modular check functions in `plugin/scripts/validators/`. Each validator is sourced by a gate dispatcher and returns exit code 0 (allow), 1 (warn), or 2 (block).

## Full List

| Validator | Gate | Severity | Description |
|-----------|------|----------|-------------|
| `agent-output.sh` | post-agent-gate | warn | Deterministic post-agent output audit — checks for stubs, deferred actions, and unmet task requirements in agent responses |
| `aggregate-session.sh` | session-end-dispatcher | allow | Session metrics aggregator — writes tool call counts, edit stats, and project type to `session_metrics` table at session end |
| `ai-safety.sh` | pre-bash-gate | warn | AI safety check — detects commands that could compromise system integrity or violate safety guidelines |
| `blind-edit.sh` | pre-edit-gate | warn | Detects edits to files that were never read in the current session — catches unresearched changes |
| `bulk-edit.sh` | pre-edit-gate | warn | Detects bulk-edit patterns — warns when the same tool is applied to many files in rapid succession |
| `dangerous-bash.sh` | pre-bash-gate | block | Blocks dangerous shell commands: `rm -rf`, force pushes, credential handling, pipe-to-shell patterns, and similar destructive operations |
| `deploy-loop-detector.sh` | post-bash-gate | block | Catches agents that repeatedly deploy without fixing the underlying issue — blocks after `failure_loop_limit` same-command failures |
| `doc-index.sh` | post-bash-gate | allow | Documentation index generator — updates doc index after edits to markdown files |
| `git-commits.sh` | task-completion-gate / session-stop-dispatcher | warn | Uncommitted changes detection — warns or blocks when modified file count exceeds `uncommitted_file_limit` |
| `localhost.sh` | pre-edit-gate | warn | Detects localhost URLs hardcoded into config files — flags `localhost:`, `127.0.0.1`, and `0.0.0.0` in non-test files |
| `memory-consolidate.sh` | session-end-dispatcher | allow | Memory consolidation — syncs memory markdown files to SQLite, applies confidence decay, prunes low-confidence entries, and regenerates MEMORY.md |
| `mesh-lock.sh` | pre-edit-gate | warn | Mesh lock check — warns if another agent holds an agent-mesh lock on the target file |
| `mocks.sh` | pre-edit-gate | warn | Mock and fake data pattern detection — warns when mock patterns appear outside test files |
| `no-deferred-actions.sh` | post-agent-gate | block | Detects when an agent lists manual steps for the user instead of executing them directly |
| `prefer-edit-over-write.sh` | pre-edit-gate | warn | Warns when the Write tool overwrites an existing file with meaningful content — nudges agents toward Edit for targeted changes |
| `ran-checks.sh` | task-completion-gate | block | Verification evidence check — blocks task completion when no typecheck, test run, or build output is present in the session output |
| `research-backing.sh` | pre-edit-gate | warn | Research backing gate — warns when code changes introduce external API calls or library usage without evidence of prior research |
| `secrets.sh` | pre-edit-gate | block | Hardcoded secret and credential detection — blocks writes containing patterns matching API keys, tokens, passwords, and private keys |
| `semantic-agent.sh` | post-agent-gate | warn | AI-assisted semantic audit of agent output — uses a secondary model call to check for logic errors, unsafe patterns, and task quality |
| `session-wrap.sh` | session-stop-dispatcher | allow | Session wrap-up runner — triggers cleanup side-effects at session end (always exits 0) |
| `stubs.sh` | pre-edit-gate | warn | Stub and placeholder detection — warns when code contains `TODO`, `FIXME`, `NotImplementedError`, empty function bodies, or similar placeholders outside test files |
| `task-done.sh` | task-completion-gate | block | Task completion verification — checks that the work described in the active task is actually reflected in the session's edits |
| `task-quality.sh` | task-completion-gate / session-stop-dispatcher | warn | Task quality gate — checks TypeScript type escape usage, UI verification, typecheck evidence, and debug workflow compliance |
| `task-scope.sh` | pre-edit-gate | warn | Enforce-task-scope — warns when an edited file is outside the inferred scope of the current task |
| `unasked-deps.sh` | pre-bash-gate | warn | Unasked dependency detection — warns when an agent installs packages that were not mentioned in the user's request |
| `unasked-restructure.sh` | pre-bash-gate | block | Block-unasked-restructure — blocks shell commands that would move, rename, or restructure files when not requested |

## Exit Code Contract

| Code | Meaning | Effect |
|------|---------|--------|
| `0` | Allow | No output required; dispatcher continues |
| `1` | Warn | Write human-readable message to stdout; dispatcher emits `{"systemMessage": "..."}` |
| `2` | Block | Write human-readable reason to stdout; dispatcher emits block JSON and exits |

Safety-critical gates (`pre-bash-gate`) stop at the first block and do not run subsequent validators. Non-safety gates accumulate all warnings before exiting.
