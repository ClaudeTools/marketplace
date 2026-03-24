---
title: "Implementation Prompt - Headless Claude Training"
created: "2026-03-16"
modified: "2026-03-16"
version: "1.0.0"
status: "active"
category: "plan"
tags: ["training", "headless", "claude-p", "automation"]
author: "claude"
---

# Implementation Prompt: Headless Claude Training via `claude -p`

Read this entire prompt before starting. This is a targeted upgrade to the training infrastructure - not a rewrite. The deterministic tests, safety corpus, BATS, and doc management tests are working and should not be touched.

## The Problem

The training runner (`tests/training/train-continuous.sh`) currently "simulates" code fixes by appending `must_contain` patterns and deleting `must_not_contain` lines with sed. This works for simple single-file edits but fundamentally cannot handle scenarios that require new file creation, multi-file coordination, or structural refactoring. 11 of 25 code scenarios always fail because of this.

The scenarios are correctly designed. The execution method is wrong.

## The Solution

Use `claude -p` (headless/pipe mode) to have Claude actually execute the scenarios. Claude Code runs non-interactively, receives the task prompt, uses tools (Read, Edit, Write, Bash) to complete it, then exits. Critically, **installed plugin hooks fire during headless execution** - meaning PreToolUse, PostToolUse, PostToolUseFailure hooks all fire naturally. This is exactly what the self-learning pipeline needs to generate real hook_outcomes data.

## Key `claude -p` Flags

```bash
claude -p "prompt"                     # Basic headless execution
  --model haiku                        # Model selection (haiku/sonnet/opus)
  --max-turns 15                       # Cap agentic turns (prevents runaway)
  --max-budget-usd 0.50                # Cost cap per scenario
  --output-format json                 # Structured output with usage/cost data
  --allowedTools "Read,Edit,Write,Bash,Grep,Glob"  # Restrict tools
  --dangerously-skip-permissions       # Fully unattended (no permission prompts)
  --no-session-persistence             # Don't save session to disk (training noise)
```

## What to Build

### 1. New file: `tests/training/headless-runner.sh`

This is a new runner specifically for interactive scenarios. It does NOT replace `train-continuous.sh` - it is called BY it for scenarios that need Claude execution.

```bash
#!/usr/bin/env bash
# headless-runner.sh - Execute a training scenario via claude -p
# Usage: headless-runner.sh <scenario.json> <workspace-dir> [--model MODEL] [--max-turns N] [--budget USD]
#
# Returns: exit 0 if scenario passed scoring, exit 1 if failed
# Outputs: JSON result to stdout

set -euo pipefail

SCENARIO_FILE="${1:?Usage: headless-runner.sh <scenario.json> <workspace-dir>}"
WORKSPACE="${2:?Usage: headless-runner.sh <scenario.json> <workspace-dir>}"
shift 2

# Defaults - haiku is cheapest, use for baseline training
MODEL="haiku"
MAX_TURNS=15
BUDGET="0.50"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Extract scenario details
NAME=$(jq -r '.name' "$SCENARIO_FILE")
TASK=$(jq -r '.task' "$SCENARIO_FILE")

# Build the prompt - tell Claude exactly what to do and where
PROMPT="You are working in the directory: $WORKSPACE

Your task:
$TASK

Instructions:
- Work only within the current directory.
- Do not ask questions. Complete the task fully.
- Do not create documentation files or READMEs.
- Do not run tests unless the task explicitly requires it.
- Focus on writing correct, production-quality code."

# Check claude CLI is available
if ! command -v claude &>/dev/null; then
  echo '{"error":"claude CLI not found","name":"'"$NAME"'"}' >&2
  exit 1
fi

# Execute via claude -p from the workspace directory
START_TIME=$(date +%s)

RESULT=$(cd "$WORKSPACE" && claude -p "$PROMPT" \
  --model "$MODEL" \
  --max-turns "$MAX_TURNS" \
  --max-budget-usd "$BUDGET" \
  --output-format json \
  --allowedTools "Read,Edit,Write,Bash(ls *),Bash(cat *),Bash(mkdir *),Bash(cp *),Bash(test *),Bash(echo *),Grep,Glob" \
  --dangerously-skip-permissions \
  --no-session-persistence \
  2>/dev/null) || RESULT='{"error":"claude -p execution failed"}'

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Extract usage data from the JSON result
COST=$(echo "$RESULT" | jq -r '.cost // 0' 2>/dev/null || echo "0")
INPUT_TOKENS=$(echo "$RESULT" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo "0")
OUTPUT_TOKENS=$(echo "$RESULT" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo "0")

# Score the actual workspace state against the scenario criteria
SCORE_OUTPUT=$(bash "$SCRIPT_DIR/scorer.sh" "$SCENARIO_FILE" "$WORKSPACE" 2>&1) || true
PASSED=$(echo "$SCORE_OUTPUT" | grep -oE 'Checks: [0-9]+' | grep -oE '[0-9]+' | head -1 || echo "0")
TOTAL=$(echo "$SCORE_OUTPUT" | grep -oE '/ [0-9]+' | grep -oE '[0-9]+' | head -1 || echo "0")
SCORE_PCT=$(echo "$SCORE_OUTPUT" | grep -oE '[0-9.]+%' | head -1 || echo "0%")

# Determine pass/fail
SUCCESS=0
[ "$PASSED" = "$TOTAL" ] && [ "$TOTAL" -gt 0 ] && SUCCESS=1

# Output structured result
jq -cn \
  --arg name "$NAME" \
  --arg model "$MODEL" \
  --argjson success "$SUCCESS" \
  --argjson passed "${PASSED:-0}" \
  --argjson total "${TOTAL:-0}" \
  --arg score "$SCORE_PCT" \
  --argjson duration "$DURATION" \
  --argjson cost "${COST:-0}" \
  --argjson input_tokens "${INPUT_TOKENS:-0}" \
  --argjson output_tokens "${OUTPUT_TOKENS:-0}" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    name: $name,
    model: $model,
    success: ($success == 1),
    passed: $passed,
    total: $total,
    score: $score,
    duration_seconds: $duration,
    cost_usd: $cost,
    input_tokens: $input_tokens,
    output_tokens: $output_tokens,
    execution: "headless",
    timestamp: $timestamp
  }'

exit $((1 - SUCCESS))
```

### 2. Add an `evaluation` field to each scenario JSON

Every scenario needs to declare whether it should be scored deterministically or via headless execution. Add this field to all 25 code scenario JSON files:

**Deterministic scenarios (14) - add `"evaluation": "deterministic"`:**
- fix-type-error, fix-import, fix-race-condition, fix-cors-config, fix-memory-leak
- add-endpoint, add-logging, add-error-boundary
- debug-null-reference, migrate-callback-to-async, optimize-query
- refactor-function, update-dependency, add-validation

**Headless scenarios (11) - add `"evaluation": "headless"`:**
- add-authentication, add-pagination, add-caching-layer, add-rate-limiting
- add-retry-logic, add-tests, fix-sql-injection
- fix-timezone-bug, fix-circular-import, fix-race-condition-db
- refactor-to-strategy-pattern

Example diff for add-authentication.json:
```json
{
  "name": "add-authentication",
+ "evaluation": "headless",
  "description": "Add JWT authentication middleware...",
  ...
}
```

### 3. Update `run_scenarios()` in `train-continuous.sh`

Replace the current `run_scenarios()` function. The key change: when a scenario has `"evaluation": "headless"`, use `headless-runner.sh` instead of the sed simulation.

Replace lines 186-278 in `train-continuous.sh` with:

```bash
run_scenarios() {
  local scenario_type="$1"
  local scenario_dir="$SCRIPT_DIR/scenarios/$scenario_type"

  if [ ! -d "$scenario_dir" ]; then
    echo "  No scenarios for: $scenario_type"
    return
  fi

  echo "[$(date +%H:%M:%S)] === Scenarios: $scenario_type ==="
  local pass=0 fail=0 skip=0 total=0

  for scenario_file in "$scenario_dir"/*.json; do
    [ ! -f "$scenario_file" ] && continue
    local name=$(jq -r '.name' "$scenario_file")
    local eval_type=$(jq -r '.evaluation // "deterministic"' "$scenario_file")
    total=$((total + 1))

    # Create workspace from scaffold
    local workspace=$(mktemp -d)
    local scaffold=$(jq -r '.scaffold // "general-project"' "$scenario_file")
    local scaffold_dir="$TESTS_DIR/scaffolds/$scaffold"

    [ -d "$scaffold_dir" ] && cp -r "$scaffold_dir"/. "$workspace"/ 2>/dev/null || true
    cd "$workspace" && git init -q 2>/dev/null && git config user.email "t@t.com" && git config user.name "T" 2>/dev/null || true

    # Run setup commands
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      (cd "$workspace" && eval "$cmd") >/dev/null 2>&1 || \
      (cd "$workspace" && bash -c "$cmd") >/dev/null 2>&1 || true
    done < <(jq -r '.setup_commands // [] | .[]' "$scenario_file" 2>/dev/null)

    local has_criteria=$(jq -r '.success_criteria // empty' "$scenario_file")

    if [ "$eval_type" = "headless" ]; then
      # ---- HEADLESS EXECUTION: Claude actually does the work ----
      if ! command -v claude &>/dev/null; then
        echo "  $name: SKIP (claude CLI not available)"
        skip=$((skip + 1))
        log_result "$scenario_type" "$name" "SKIP" "claude CLI not available"
        rm -rf "$workspace" 2>/dev/null || true
        continue
      fi

      echo -n "  $name [headless/$TRAINING_MODEL]: "

      local headless_result
      headless_result=$(bash "$SCRIPT_DIR/headless-runner.sh" \
        "$scenario_file" "$workspace" \
        --model "${TRAINING_MODEL:-haiku}" \
        --max-turns "${TRAINING_MAX_TURNS:-15}" \
        --budget "${TRAINING_BUDGET:-0.50}" \
        2>/dev/null) || true

      local h_success=$(echo "$headless_result" | jq -r '.success // false' 2>/dev/null)
      local h_score=$(echo "$headless_result" | jq -r '.score // "0%"' 2>/dev/null)
      local h_cost=$(echo "$headless_result" | jq -r '.cost_usd // 0' 2>/dev/null)
      local h_duration=$(echo "$headless_result" | jq -r '.duration_seconds // 0' 2>/dev/null)

      if [ "$h_success" = "true" ]; then
        pass=$((pass + 1))
        log_result "$scenario_type" "$name" "PASS" "headless:${h_score}:cost=\$${h_cost}:${h_duration}s"
        classify_scenario_outcomes "$name" "PASS" "$SESSION_ID"
        echo "PASS ($h_score, \$$h_cost, ${h_duration}s)"
      else
        fail=$((fail + 1))
        log_result "$scenario_type" "$name" "FAIL" "headless:${h_score}:cost=\$${h_cost}:${h_duration}s"
        classify_scenario_outcomes "$name" "FAIL" "$SESSION_ID"
        echo "FAIL ($h_score, \$$h_cost, ${h_duration}s)"
      fi

      # Append headless result to dedicated log
      echo "$headless_result" >> "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null || true

    elif [ -n "$has_criteria" ]; then
      # ---- DETERMINISTIC: Simulate fix with sed/append (existing logic) ----
      local must_contain=$(jq -r '.success_criteria.must_contain // [] | .[]' "$scenario_file" 2>/dev/null || true)
      local must_not_contain=$(jq -r '.success_criteria.must_not_contain // [] | .[]' "$scenario_file" 2>/dev/null || true)
      local files_modified=$(jq -r '.success_criteria.files_modified // [] | .[]' "$scenario_file" 2>/dev/null || true)

      if [ -n "$files_modified" ]; then
        while IFS= read -r target_file; do
          [ -z "$target_file" ] && continue
          local full_path="$workspace/$target_file"
          [ ! -f "$full_path" ] && continue

          while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            grep -q "$pattern" "$full_path" 2>/dev/null || echo "$pattern" >> "$full_path"
          done <<< "$must_contain"

          while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            sed -i '' "/$pattern/d" "$full_path" 2>/dev/null || sed -i "/$pattern/d" "$full_path" 2>/dev/null || true
          done <<< "$must_not_contain"
        done <<< "$files_modified"
      fi

      if bash "$SCRIPT_DIR/scorer.sh" "$scenario_file" "$workspace" > "$RESULTS_DIR/${name}-score.log" 2>&1; then
        pass=$((pass + 1))
        log_result "$scenario_type" "$name" "PASS" "deterministic"
        classify_scenario_outcomes "$name" "PASS" "$SESSION_ID"
        echo "  $name: PASS [deterministic]"
      else
        fail=$((fail + 1))
        log_result "$scenario_type" "$name" "FAIL" "deterministic"
        classify_scenario_outcomes "$name" "FAIL" "$SESSION_ID"
        echo "  $name: FAIL [deterministic]"
      fi

    else
      # ---- SEMANTIC: Non-code/behavioural scenarios ----
      pass=$((pass + 1))
      log_result "$scenario_type" "$name" "PASS" "exercised (semantic)"
      classify_scenario_outcomes "$name" "PASS" "$SESSION_ID"
      echo "  $name: EXERCISED [semantic]"
    fi

    rm -rf "$workspace" 2>/dev/null || true
  done

  echo "  $scenario_type: $pass/$total passed ($fail failed, $skip skipped)"
}
```

### 4. Add training configuration variables to `train-continuous.sh`

Add these after the existing `SESSION_ID` line (line 41):

```bash
# Headless training configuration
TRAINING_MODEL="${TRAINING_MODEL:-haiku}"       # Default to cheapest model
TRAINING_MAX_TURNS="${TRAINING_MAX_TURNS:-15}"   # Cap turns per scenario
TRAINING_BUDGET="${TRAINING_BUDGET:-0.50}"       # USD cap per scenario
export TRAINING_SESSION_ID="$SESSION_ID"         # Ensure hooks can see session ID
```

Also add CLI args for model selection. In the arg parser (lines 22-29), add:

```bash
    --model) TRAINING_MODEL="$2"; shift 2 ;;
    --max-turns) TRAINING_MAX_TURNS="$2"; shift 2 ;;
    --budget) TRAINING_BUDGET="$2"; shift 2 ;;
```

### 5. Update the `/train` skill SKILL.md

Add a new command section for headless training to `skills/train/SKILL.md`:

Add after the existing `/train edge` section:

```markdown
### /train headless
Run ONLY the headless (interactive) scenarios using `claude -p`.
These are scenarios that require Claude to create files, refactor code, and make multi-file changes.
```bash
TRAINING_MODEL=haiku bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh \
  --iterations 1 --domain code
```
Note: Only scenarios with `"evaluation": "headless"` will use Claude execution.
Deterministic scenarios still run with the sed simulator.

### /train compare-models
Run all headless scenarios across haiku, sonnet, and opus to compare.
```bash
for model in haiku sonnet opus; do
  echo "=== Model: $model ==="
  TRAINING_MODEL=$model bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-continuous.sh \
    --iterations 1 --domain code
done
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/report.sh
```
```

### 6. Update `report.sh` to show headless vs deterministic results separately

In `tests/training/report.sh`, add a section that reads from `headless-log.jsonl` and reports:

- Per-scenario pass rate across iterations
- Average cost per scenario
- Average duration per scenario
- Model comparison if multiple models were used
- Total training spend

Parse headless results with:
```bash
if [ -f "$RESULTS_DIR/headless-log.jsonl" ]; then
  echo ""
  echo "=== Headless Execution Results ==="
  echo ""

  # Per-model summary
  for model in haiku sonnet opus; do
    local count=$(jq -r "select(.model==\"$model\") | .name" "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] && continue

    local passes=$(jq -r "select(.model==\"$model\" and .success==true) | .name" "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null | wc -l | tr -d ' ')
    local total_cost=$(jq -r "select(.model==\"$model\") | .cost_usd" "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null | awk '{s+=$1}END{printf "%.4f", s}')
    local avg_duration=$(jq -r "select(.model==\"$model\") | .duration_seconds" "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null | awk '{s+=$1; n++}END{printf "%.0f", s/n}')

    echo "  Model: $model"
    echo "    Scenarios: $passes/$count passed"
    echo "    Total cost: \$$total_cost"
    echo "    Avg duration: ${avg_duration}s per scenario"
    echo ""
  done

  # Per-scenario breakdown
  echo "  Per-scenario results:"
  jq -r '[.name, .model, (if .success then "PASS" else "FAIL" end), .score, ("$" + (.cost_usd | tostring)), (.duration_seconds | tostring + "s")] | join(" | ")' \
    "$RESULTS_DIR/headless-log.jsonl" 2>/dev/null | sort | while read -r line; do
    echo "    $line"
  done
fi
```

---

## Cost Controls

This is important. Headless execution costs real tokens. The defaults are conservative:

| Control | Default | Purpose |
|---|---|---|
| `TRAINING_MODEL` | haiku | Cheapest model for baseline |
| `TRAINING_MAX_TURNS` | 15 | Prevents runaway agents |
| `TRAINING_BUDGET` | $0.50 | Per-scenario cost cap |
| `--allowedTools` | Read,Edit,Write,Bash(safe),Grep,Glob | No dangerous bash, no web |

**Estimated costs per run:**

- Haiku: ~$0.02-0.10 per scenario, ~$1.10-2.50 for all 11 headless scenarios
- Sonnet: ~$0.10-0.50 per scenario, ~$1.10-5.50 for all 11
- Opus: ~$0.50-2.00 per scenario, ~$5.50-22.00 for all 11

Default full training iteration (all domains): ~$1-3 with haiku.

The `--max-budget-usd` flag is a hard stop - Claude exits if the scenario exceeds it. Combined with `--max-turns 15`, a runaway scenario is capped at roughly $0.50.

---

## What NOT to Change

- `run_deterministic()` - Leave as-is. BATS and Vitest work fine.
- `run_safety()` - Leave as-is. Safety corpus test works fine.
- `run_docs()` - Leave as-is. Doc management tests work fine.
- `scorer.sh` - Leave as-is. It already scores workspace state correctly.
- `runner.sh` - Leave as-is. It's a manual/interactive runner. Different purpose.
- Any existing BATS tests, fixtures, or scaffolds.

---

## Execution Order

1. Add `"evaluation"` field to all 25 code scenario JSONs
2. Create `tests/training/headless-runner.sh` (make executable)
3. Update `train-continuous.sh` with the new `run_scenarios()` and config vars
4. Update `skills/train/SKILL.md` with new commands
5. Update `tests/training/report.sh` with headless reporting
6. Test with a single scenario first:
   ```bash
   bash tests/training/headless-runner.sh \
     tests/training/scenarios/code/add-validation.json \
     /tmp/test-workspace \
     --model haiku
   ```
7. Run a full iteration:
   ```bash
   TRAINING_MODEL=haiku bash tests/training/train-continuous.sh --iterations 1 --domain code
   ```
8. Verify hook_outcomes are being recorded with real session IDs
9. Verify scorer is evaluating Claude's actual output (not sed simulations)
10. Commit and push

---

## Why This Matters

Right now the training pipeline has a dead zone: 11 scenarios that always fail because the scorer can't simulate what Claude does. With headless execution:

- Those 11 scenarios get real scores (some may still fail, but now it's Claude's performance, not the scorer's limitation)
- Every tool call during headless execution fires the plugin hooks naturally
- `hook_outcomes` table gets populated with data from diverse hooks (edit-frequency-guard, verify-no-stubs, failure-pattern-detector, etc.) not just block-dangerous-bash
- The adaptive tuning algorithm gets the classified data it needs to start making real threshold adjustments
- Model comparison becomes meaningful because you're comparing actual execution quality, not sed output

The self-learning loop closes: hooks fire -> outcomes captured -> sessions aggregated -> thresholds tuned -> hooks read new thresholds -> hooks fire with adjusted behaviour.
