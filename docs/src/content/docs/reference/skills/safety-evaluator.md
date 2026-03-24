---
title: "Evaluating Safety"
description: "Skill for running safety corpus evaluations, deterministic tests, and multi-model comparisons with closed-loop feedback."
---

> **Status:** 🆕 New in v3.1 — added with the training infrastructure in the v3.1.0 release

Run training scenarios, deterministic tests, and safety corpus evaluations. Supports single-domain commands, multi-model comparisons, golden test suites, and closed-loop feedback pipelines.

**Trigger:** Use when the user says "train", "run training", "test safety", "run scenarios", "evaluate model", or "compare results".

**Invocation:** `/safety-evaluator [command] [options]`

---

## When to use this

Use this skill when you want to verify that safety hooks and validators are actually catching the scenarios they're supposed to catch. It's most useful after changing hook thresholds, adding new validators, or before publishing a plugin update — run the test suite to confirm nothing regressed. You can also use it to compare how different Claude models handle edge cases before choosing one for a production deployment.

---

## Try it now

```
/safety-evaluator test
```

This runs the full test suite across all scenario domains. Expect output showing pass/fail counts per scenario, any threshold violations, and a summary report. To preview findings without running live tests, use `--dry-run` with `feedback-loop`.

---

## Commands

### Single-Domain (run directly via Bash)

| Command | What it runs |
|---------|-------------|
| `test` | Full test suite via `make test-all` |
| `code` | All scenarios in `scenarios/code/` |
| `noncode` | All scenarios in `scenarios/non-code/` |
| `edge` | All scenarios in `scenarios/edge-cases/` |
| `headless` | Continuous training loop (1 iteration, code domain, sonnet model) |
| `golden` | SWE-bench golden tests (10 tasks, ~$0.50-2.00 cost) |
| `compare` | Training report across recent runs |
| `cross-model-dry-run` | Tune weights dry run |

### Chain Commands

| Command | What it runs |
|---------|-------------|
| `chain <name>` | Run a single prompt chain by name |
| `discover-gaps` | Analyze recent deviations, find recurring failure patterns |
| `feedback-loop` | Full closed-loop: discover gaps → adjust thresholds → re-run → commit or rollback (defaults to `--dry-run`) |

### Multi-Model (use TeamCreate)

| Command | What it runs |
|---------|-------------|
| `cross-model` | Run all scenarios across multiple models in parallel |
| `golden-cross-model` | Golden tests across all configured models |
| `all` | Full evaluation: all domains + all models |

---

## Example Invocations

```
/safety-evaluator test
/safety-evaluator code
/safety-evaluator golden
/safety-evaluator chain auth-bypass
/safety-evaluator feedback-loop
/safety-evaluator cross-model
```

---

## Notes

- The `feedback-loop` command defaults to `--dry-run`. Remove the flag in the script for live threshold adjustments.
- The `golden` command downloads SWE-bench data on first run (~2 min).
- Multi-model commands use TeamCreate for parallel execution across model variants.

---

## Related Components

- **tests/training/** — scenario JSON files, runner script, chain definitions
- **tests/golden/** — golden test suite and SWE-bench integration
- **scripts/tune-weights.sh** — threshold tuning used by `cross-model-dry-run`
- **plugin-improver skill** — uses training data as part of the self-improvement loop
