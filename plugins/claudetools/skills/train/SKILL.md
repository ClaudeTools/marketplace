---
name: train
description: Run training scenarios, deterministic tests, and safety corpus evaluations. Use when the user says train, run training, test safety, run scenarios, evaluate model, or compare results.
argument-hint: <command> [test|code|noncode|edge|compare|cross-model|cross-model-dry-run|all]
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: general-purpose
metadata:
  author: Owen Innes
  version: 1.0.0
  category: testing
  tags: [training, testing, safety, evaluation, scenarios]
---

# Training System

Run training scenarios and deterministic tests for the claudetools plugin.

## Commands

The first argument selects the command to run:

### test
Run all deterministic tests (BATS + vitest + safety corpus).

```bash
cd "${CLAUDE_PLUGIN_ROOT}/tests" && make test-all
```

### code
Run code training scenarios.

```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/code"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### noncode
Run non-code training scenarios.

```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/non-code"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### edge
Run edge case scenarios.

```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/edge-cases"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### headless
Run ONLY the headless (interactive) scenarios using `claude -p`.
These are scenarios that require Claude to create files, refactor code, and make multi-file changes.

```bash
TRAINING_MODEL=haiku bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh \
  --iterations 1 --domain code
```

Note: Only scenarios with `"evaluation": "headless"` will use Claude execution.
Deterministic scenarios still run with the sed simulator.

### compare-models
Run all headless scenarios across haiku, sonnet, and opus to compare.

```bash
for model in haiku sonnet opus; do
  echo "=== Model: $model ==="
  TRAINING_MODEL=$model bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh \
    --iterations 1 --domain code
done
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh
```

### cross-model
Run all headless scenarios across haiku, sonnet, and opus with per-model threshold tuning.
Generates per-model comparison data and writes per-model weight multipliers to model_profiles.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-cross-model.sh
```

Estimated cost: ~$8-30 depending on scenario complexity.
After completion, model_profiles table will have per-hook per-model multipliers
that are automatically applied when users run the plugin with different models.

### cross-model-dry-run
Preview what threshold adjustments would be made without applying them.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/tune-weights.sh --dry-run
```

### golden
Run golden reference tests against SWE-bench tasks.
Compares Claude's output against known-correct human patches.
Identifies behavioral anti-patterns and guardrail gaps.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh haiku 10
```

First run downloads SWE-bench data (~2 min).
Each task clones a real GitHub repo, runs Claude headless, diffs against gold.
Estimated cost: ~$0.50-2.00 for 10 tasks with haiku.

### golden-cross-model
Run same golden tasks across all models to compare behavioral patterns.

```bash
for model in haiku sonnet opus; do
  bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh $model 10
done
bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/analyse-deviations.sh
```

### compare
Generate comparison report from training results.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh"
```

### all
Run everything: deterministic tests, then all scenario types, then generate report.

1. Run `test` command
2. Run `code` command
3. Run `noncode` command
4. Run `edge` command
5. Run `compare` command

## Workflow

1. Parse the command argument (default: `test`)
2. Execute the appropriate command(s)
3. Report results to the user
4. If any tests fail, list the failures clearly
