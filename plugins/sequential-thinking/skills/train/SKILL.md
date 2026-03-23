---
name: train
description: Run training scenarios, deterministic tests, and safety corpus evaluations. Use when the user says train, run training, test safety, run scenarios, evaluate model, or compare results.
argument-hint: <command> [test|code|noncode|edge|compare|cross-model|cross-model-dry-run|golden|golden-cross-model|all]
allowed-tools: Read, Bash, Grep, Glob, Agent, TeamCreate, TeamDelete, TaskCreate, TaskUpdate, TaskList, SendMessage
context: fork
agent: general-purpose
metadata:
  author: Owen Innes
  version: 2.1.0
  category: testing
  tags: [training, testing, safety, evaluation, scenarios, teams]
---

# Training System

You are executing the `/train` skill. Follow these instructions exactly.

Parse the first argument to select the command. Default to `test` if no argument is given.

---

## Single-domain commands — run directly via Bash

These commands run a single bash command. Do NOT use TeamCreate for these.

### test
```bash
cd "${CLAUDE_PLUGIN_ROOT}/tests" && make test-all
```

### code
```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/code"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### noncode
```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/non-code"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### edge
```bash
SCENARIOS_DIR="${CLAUDE_PLUGIN_ROOT}/tests/training/scenarios/edge-cases"
for f in "$SCENARIOS_DIR"/*.json; do
  bash "${CLAUDE_PLUGIN_ROOT}/tests/training/runner.sh" "$f"
done
```

### headless
```bash
TRAINING_MODEL=sonnet bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh \
  --iterations 1 --domain code
```

### golden
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh sonnet 10
```

First run downloads SWE-bench data (~2 min). Estimated cost: ~$0.50-2.00 for 10 tasks with haiku.

### compare
```bash
bash "${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh"
```

### cross-model-dry-run
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/tune-weights.sh --dry-run
```

### chain
Run a single prompt chain with the default model. Argument: chain name (matches filename in chains/ without .json).
```bash
CHAIN_FILE="${CLAUDE_PLUGIN_ROOT}/tests/training/chains/${ARGS}.json"
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/chain-runner.sh "$CHAIN_FILE" --model sonnet
```

### discover-gaps
Run gap discovery on recent deviations from chain executions.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/discover-gaps.sh --min-frequency 0.10 --since 30
```

### feedback-loop
Run the full closed-loop pipeline: discover gaps, adjust thresholds, re-run chains, commit or rollback.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/feedback-loop.sh --dry-run --top-k 3 --model sonnet
```
Note: Defaults to --dry-run for safety. Remove --dry-run for live adjustments.

---

## Chain commands — use TeamCreate for cross-model and pass-k

### chain-cross
Run a chain across haiku/sonnet/opus in parallel.

1. Call `TeamCreate` with `team_name: "chain-cross-YYYYMMDD-HHMMSS"`.
2. Call the `Agent` tool three times in a single response (parallel):

   **Teammate 1:**
   - `team_name`: the team name from step 1
   - `name`: `"chain-haiku"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the full JSON result: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/chain-runner.sh ${CLAUDE_PLUGIN_ROOT}/tests/training/chains/${ARGS}.json --model haiku"`

   **Teammate 2:**
   - `team_name`: the team name from step 1
   - `name`: `"chain-sonnet"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the full JSON result: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/chain-runner.sh ${CLAUDE_PLUGIN_ROOT}/tests/training/chains/${ARGS}.json --model sonnet"`

   **Teammate 3:**
   - `team_name`: the team name from step 1
   - `name`: `"chain-opus"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the full JSON result: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/chain-runner.sh ${CLAUDE_PLUGIN_ROOT}/tests/training/chains/${ARGS}.json --model opus"`

3. Wait for all three teammates to finish.
4. Report the cross-model comparison table.
5. Call `TeamDelete`.

### pass-k
Run a chain K times for consistency measurement. Argument format: `<chain-name> [K]` (default K=5).

1. Parse the chain name and K from arguments. Default K=5 if not specified.
2. Call `TeamCreate` with `team_name: "pass-k-YYYYMMDD-HHMMSS"`.
3. Call the `Agent` tool K times in a single response (parallel), one per trial:

   For each trial N from 1 to K:
   - `team_name`: the team name from step 2
   - `name`: `"trial-N"` (e.g., "trial-1", "trial-2")
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the full JSON result: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/chain-runner.sh ${CLAUDE_PLUGIN_ROOT}/tests/training/chains/<chain-name>.json --model sonnet --trial N"`

4. Wait for all teammates to finish.
5. Collect results, compute pass^k, pass@k, consistency, step fragility.
6. Report the pass^k summary table.
7. Call `TeamDelete`.

Alternatively, for sequential execution (cheaper):
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/pass-k-runner.sh ${CLAUDE_PLUGIN_ROOT}/tests/training/chains/${CHAIN_NAME}.json --k ${K:-5} --model sonnet
```

---

## Parallel commands — you MUST use TeamCreate and spawn teammate agents

For every command below, you MUST call the TeamCreate tool first, then use the Agent tool to spawn each teammate. Do NOT just run bash commands sequentially — the whole point is parallel execution via teammates in separate tmux windows.

### all

1. First, run tests sequentially (must pass before proceeding):
   ```bash
   cd "${CLAUDE_PLUGIN_ROOT}/tests" && make test-all
   ```
2. Call `TeamCreate` with `team_name: "train-all-YYYYMMDD-HHMMSS"` (use the current date/time).
3. Call the `Agent` tool three times in a single response (parallel) to spawn three teammates:

   **Teammate 1:**
   - `team_name`: the team name from step 2
   - `name`: `"train-code"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain code"`

   **Teammate 2:**
   - `team_name`: the team name from step 2
   - `name`: `"train-noncode"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain noncode"`

   **Teammate 3:**
   - `team_name`: the team name from step 2
   - `name`: `"train-edge"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain edge"`

4. Wait for all three teammates to finish.
5. Run `bash "${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh"` to generate the comparison report.
6. Call `TeamDelete` to clean up the team.

### compare-models

1. Call `TeamCreate` with `team_name: "compare-models-YYYYMMDD-HHMMSS"`.
2. Call the `Agent` tool three times in a single response (parallel):

   **Teammate 1:**
   - `team_name`: the team name from step 1
   - `name`: `"train-haiku"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=haiku bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain code"`

   **Teammate 2:**
   - `team_name`: the team name from step 1
   - `name`: `"train-sonnet"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=sonnet bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain code"`

   **Teammate 3:**
   - `team_name`: the team name from step 1
   - `name`: `"train-opus"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=opus bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain code"`

3. Wait for all three teammates to finish.
4. Run `bash "${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh"`.
5. Call `TeamDelete`.

### cross-model

Estimated cost: ~$8-30 depending on scenario complexity.

1. Call `TeamCreate` with `team_name: "cross-model-YYYYMMDD-HHMMSS"`.
2. Call the `Agent` tool three times in a single response (parallel):

   **Teammate 1:**
   - `team_name`: the team name from step 1
   - `name`: `"cross-haiku"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=haiku bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain all"`

   **Teammate 2:**
   - `team_name`: the team name from step 1
   - `name`: `"cross-sonnet"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=sonnet bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain all"`

   **Teammate 3:**
   - `team_name`: the team name from step 1
   - `name`: `"cross-opus"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: TRAINING_MODEL=opus bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh --iterations 1 --domain all"`

3. Wait for all three teammates to finish.
4. Run `bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-cross-model.sh` for threshold tuning.
5. Call `TeamDelete`.

### golden-cross-model

1. Call `TeamCreate` with `team_name: "golden-cross-YYYYMMDD-HHMMSS"`.
2. Call the `Agent` tool three times in a single response (parallel):

   **Teammate 1:**
   - `team_name`: the team name from step 1
   - `name`: `"golden-haiku"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh haiku 10"`

   **Teammate 2:**
   - `team_name`: the team name from step 1
   - `name`: `"golden-sonnet"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh sonnet 10"`

   **Teammate 3:**
   - `team_name`: the team name from step 1
   - `name`: `"golden-opus"`
   - `isolation`: `"worktree"`
   - `prompt`: `"You are a training runner. Run this command and report the exit code, any failures, and a one-line summary: bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh opus 10"`

3. Wait for all three teammates to finish.
4. Run `bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/analyse-deviations.sh`.
5. Call `TeamDelete`.

---

## After any command completes

- Report results to the user clearly
- If any tests or scenarios failed, list the failures
