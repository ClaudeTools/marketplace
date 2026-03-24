---
title: "Evaluating Safety"
description: "Evaluating Safety — claudetools documentation."
---
Run training scenarios, deterministic tests, and safety corpus evaluations. Supports single-domain commands, multi-model comparisons, golden test suites, and closed-loop feedback pipelines.

**Trigger:** Use when the user says "train", "run training", "test safety", "run scenarios", "evaluate model", or "compare results".

**Invocation:** `/evaluating-safety [command] [options]`

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
/evaluating-safety test
/evaluating-safety code
/evaluating-safety golden
/evaluating-safety chain auth-bypass
/evaluating-safety feedback-loop
/evaluating-safety cross-model
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
