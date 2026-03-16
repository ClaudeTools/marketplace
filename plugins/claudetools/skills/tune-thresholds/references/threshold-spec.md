# Threshold Specification

## Tunable Thresholds

### edit_frequency_limit
- **Default:** 8 edits per file per session
- **Controls:** Maximum number of times the same file can be edited before a stop-gate triggers
- **Raising:** Allows more iterative editing on complex files (reduces false positives on legitimate refactors)
- **Lowering:** Catches edit churn earlier (useful if sessions frequently spin on the same file)

### failure_loop_limit
- **Default:** 5 consecutive failures
- **Controls:** Number of consecutive tool failures before the session is paused for review
- **Raising:** Tolerates more retries (useful for flaky environments or network-dependent tools)
- **Lowering:** Stops loops faster (useful if failures rarely self-resolve)

### stub_sensitivity
- **Default:** 0.7 (0.0 = off, 1.0 = strict)
- **Controls:** How aggressively the system flags placeholder/stub code (TODO, unimplemented, empty bodies)
- **Raising:** Catches more partial implementations before they get committed
- **Lowering:** Permits intentional stubs (useful during scaffolding or phased builds)

## Safety Bounds

All thresholds are constrained to **[0.5x, 2.0x]** of their default value:

| Threshold              | Min   | Max   |
|------------------------|-------|-------|
| edit_frequency_limit   | 4     | 16    |
| failure_loop_limit     | 2     | 10    |
| stub_sensitivity       | 0.35  | 1.0   |

Thresholds can never go below half or above double their default. This prevents
runaway tuning from disabling guardrails or making them unusably strict.

## Immutable Rules (Never Tunable)

The following guardrails are hardcoded and cannot be adjusted by threshold tuning:

- **Blocked commands:** Destructive git operations (push --force to main, reset --hard, clean -fd)
- **Sensitive file protection:** .env, credentials, private keys, secrets
- **Permission patterns:** No privilege escalation, no sudo without user confirmation
- **Commit hooks:** Pre-commit validation (typecheck, lint) cannot be skipped
- **Scope limits:** Maximum file count per operation, maximum line deletions per edit
