---
title: "Implementation Prompt - Golden Reference Testing and Guardrail Discovery"
created: "2026-03-16"
modified: "2026-03-16"
version: "1.0.0"
status: "active"
category: "plan"
tags: ["testing", "swe-bench", "guardrail-discovery", "behavioral-analysis"]
author: "claude"
---

# Implementation Prompt: Golden Reference Testing for Guardrail Discovery

Read this entire prompt before starting. This is a fundamentally different approach to training than what exists. The current training tunes thresholds on existing hooks. This discovers what hooks are MISSING by comparing Claude's output against known-correct human-written code.

## The Concept

We have access to real coding tasks where humans wrote the correct solution. We run Claude headless on those same tasks. We diff the output. Every deviation is either:
- A valid alternative (Claude solved it differently but correctly)
- A real problem that no hook caught (guardrail gap)

The guardrail gaps are what we're after. Each one is a candidate for a new hook.

## Data Sources

### Primary: SWE-bench Verified (500 tasks)

Real GitHub issues from mature Python projects (Django, Flask, scikit-learn, sympy, etc.) with human-written patches and test suites.

- **Repo:** https://github.com/princeton-nlp/SWE-bench
- **Data:** https://huggingface.co/datasets/SWE-bench/SWE-bench_Verified
- **Format:** Each entry has: `instance_id`, `problem_statement` (the issue text), `patch` (gold solution), `test_patch` (tests), `repo`, `base_commit`
- **Size:** 500 verified instances (start with 20-30 for initial discovery)

```python
# Download
pip install datasets
from datasets import load_dataset
ds = load_dataset("SWE-bench/SWE-bench_Verified", split="test")
# Each row: ds[0]['instance_id'], ds[0]['problem_statement'], ds[0]['patch'], ds[0]['test_patch']
```

### Secondary: EvalPlus (164 problems, 80x test coverage)

Function-level problems with massively expanded test suites that catch silent failures.

- **Repo:** https://github.com/evalplus/evalplus
- **Install:** `pip install evalplus`
- **Access:** `evalplus.data.get_human_eval_plus()` returns problems with augmented tests

### Tertiary: RealWorld (architecture reference)

Full-stack reference implementations of the same app across frameworks.

- **Repo:** https://github.com/gothinkster/realworld
- **Use:** Compare Claude's architectural choices against human reference implementations
- **Best for:** Detecting pattern anti-patterns (monolithic vs modular, wrong abstractions, etc.)

## What to Build

### Phase 1: SWE-bench Runner

New directory: `tests/golden/`

#### 1.1 Download and prepare tasks

Create `tests/golden/setup-swebench.sh`:

```bash
#!/usr/bin/env bash
# Download SWE-bench Verified subset for golden reference testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
TASKS_DIR="$SCRIPT_DIR/tasks"
mkdir -p "$DATA_DIR" "$TASKS_DIR"

# Download via Python (HuggingFace datasets)
python3 -c "
from datasets import load_dataset
import json, os

ds = load_dataset('SWE-bench/SWE-bench_Verified', split='test')

# Export first 30 tasks (diverse repos, manageable size)
# Filter for smaller patches (< 100 lines) for faster iteration
tasks = []
for row in ds:
    patch_lines = row['patch'].count('\n')
    if patch_lines < 100 and len(tasks) < 30:
        tasks.append({
            'instance_id': row['instance_id'],
            'repo': row['repo'],
            'problem_statement': row['problem_statement'],
            'gold_patch': row['patch'],
            'test_patch': row['test_patch'],
            'base_commit': row['base_commit'],
            'patch_line_count': patch_lines,
        })

# Save individual task files
for task in tasks:
    fname = task['instance_id'].replace('/', '_').replace('__', '_')
    with open(os.path.join('$TASKS_DIR', f'{fname}.json'), 'w') as f:
        json.dump(task, f, indent=2)

print(f'Exported {len(tasks)} tasks')
for t in tasks:
    print(f'  {t[\"instance_id\"]} ({t[\"repo\"]}, {t[\"patch_line_count\"]} lines)')
"

echo "Tasks saved to $TASKS_DIR/"
```

#### 1.2 Golden reference runner

Create `tests/golden/golden-runner.sh`:

```bash
#!/usr/bin/env bash
# Run a SWE-bench task via claude -p and compare against gold patch
# Usage: golden-runner.sh <task.json> [--model MODEL]
set -euo pipefail

TASK_FILE="${1:?Usage: golden-runner.sh <task.json> [--model MODEL]}"
shift

MODEL="haiku"
MAX_TURNS=20
BUDGET="1.00"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

# Parse task
INSTANCE_ID=$(jq -r '.instance_id' "$TASK_FILE")
REPO=$(jq -r '.repo' "$TASK_FILE")
PROBLEM=$(jq -r '.problem_statement' "$TASK_FILE")
GOLD_PATCH=$(jq -r '.gold_patch' "$TASK_FILE")
BASE_COMMIT=$(jq -r '.base_commit' "$TASK_FILE")

echo "=== Golden Reference Test: $INSTANCE_ID ==="
echo "Repo: $REPO | Model: $MODEL"

# Clone the repo at the base commit
WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT

echo "Cloning $REPO at $BASE_COMMIT..."
git clone --quiet "https://github.com/$REPO.git" "$WORKSPACE/repo" 2>/dev/null
cd "$WORKSPACE/repo"
git checkout --quiet "$BASE_COMMIT" 2>/dev/null

# Set model env for hooks
case "$MODEL" in
  haiku) export CLAUDE_MODEL="claude-haiku-4-5" ;;
  sonnet) export CLAUDE_MODEL="claude-sonnet-4-6" ;;
  opus) export CLAUDE_MODEL="claude-opus-4-6" ;;
  *) export CLAUDE_MODEL="$MODEL" ;;
esac

# Build the prompt
PROMPT="You are fixing a bug in the $REPO repository.

Here is the issue:

$PROBLEM

Fix this issue. Make the minimal necessary changes. Do not refactor unrelated code. Do not add comments explaining what you changed. Just fix the bug."

# Run Claude headless
START_TIME=$(date +%s)

CLAUDE_RESULT=$(claude -p "$PROMPT" \
  --model "$MODEL" \
  --max-turns "$MAX_TURNS" \
  --max-budget-usd "$BUDGET" \
  --output-format json \
  --allowedTools "Read,Edit,Write,Bash(git diff*),Bash(find *),Bash(ls *),Bash(cat *),Bash(python*),Bash(pip*),Grep,Glob" \
  --dangerously-skip-permissions \
  --no-session-persistence \
  2>/dev/null) || CLAUDE_RESULT='{"error":"claude -p failed"}'

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Capture Claude's patch (what it actually changed)
CLAUDE_PATCH=$(git diff 2>/dev/null || echo "")

# If Claude used Write instead of Edit, also check untracked files
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$UNTRACKED" ]; then
  git add -A 2>/dev/null
  CLAUDE_PATCH=$(git diff --cached 2>/dev/null || echo "")
fi

COST=$(echo "$CLAUDE_RESULT" | jq -r '.cost // 0' 2>/dev/null || echo "0")

# Save Claude's patch
RESULT_PREFIX="$RESULTS_DIR/$(echo "$INSTANCE_ID" | tr '/' '_')-$MODEL"
echo "$CLAUDE_PATCH" > "${RESULT_PREFIX}-claude.patch"
echo "$GOLD_PATCH" > "${RESULT_PREFIX}-gold.patch"

# === ANALYSIS PHASE ===

# 1. Did Claude produce any patch at all?
if [ -z "$CLAUDE_PATCH" ]; then
  echo "  RESULT: NO_PATCH (Claude made no changes)"
  jq -cn \
    --arg id "$INSTANCE_ID" --arg model "$MODEL" \
    --arg result "NO_PATCH" --argjson duration "$DURATION" \
    --argjson cost "${COST:-0}" \
    '{instance_id:$id, model:$model, result:$result, duration:$duration, cost:$cost}' \
    > "${RESULT_PREFIX}-result.json"
  exit 1
fi

# 2. Files touched comparison
GOLD_FILES=$(echo "$GOLD_PATCH" | grep '^diff --git' | sed 's|diff --git a/\(.*\) b/.*|\1|' | sort)
CLAUDE_FILES=$(echo "$CLAUDE_PATCH" | grep '^diff --git' | sed 's|diff --git a/\(.*\) b/.*|\1|' | sort)

FILES_MATCH="false"
[ "$GOLD_FILES" = "$CLAUDE_FILES" ] && FILES_MATCH="true"

# Files Claude touched that gold didn't (over-modification)
EXTRA_FILES=$(comm -23 <(echo "$CLAUDE_FILES") <(echo "$GOLD_FILES") 2>/dev/null || true)

# Files gold touched that Claude missed (under-modification)
MISSED_FILES=$(comm -13 <(echo "$CLAUDE_FILES") <(echo "$GOLD_FILES") 2>/dev/null || true)

# 3. Patch size comparison
GOLD_LINES=$(echo "$GOLD_PATCH" | grep -c '^[+-]' 2>/dev/null || echo "0")
CLAUDE_LINES=$(echo "$CLAUDE_PATCH" | grep -c '^[+-]' 2>/dev/null || echo "0")

# Size ratio (Claude vs Gold). >1.5 means Claude wrote 50%+ more code
if [ "$GOLD_LINES" -gt 0 ]; then
  SIZE_RATIO=$(awk "BEGIN {printf \"%.2f\", $CLAUDE_LINES / $GOLD_LINES}")
else
  SIZE_RATIO="0"
fi

# 4. Apply Claude's patch and run gold tests (if possible)
TEST_RESULT="SKIPPED"
# Reset to base
git checkout -- . 2>/dev/null
git clean -fd 2>/dev/null

# Apply Claude's changes
echo "$CLAUDE_PATCH" | git apply --allow-empty 2>/dev/null && {
  # Try to apply test patch and run tests
  # (SWE-bench test patches add new test cases that validate the fix)
  TEST_PATCH=$(jq -r '.test_patch' "$TASK_FILE")
  if [ -n "$TEST_PATCH" ] && [ "$TEST_PATCH" != "null" ]; then
    echo "$TEST_PATCH" | git apply --allow-empty 2>/dev/null && {
      # Run pytest on the test files from the test patch
      TEST_FILES=$(echo "$TEST_PATCH" | grep '^diff --git' | sed 's|diff --git a/\(.*\) b/.*|\1|')
      if [ -n "$TEST_FILES" ]; then
        TEST_OUTPUT=$(timeout 120 python -m pytest $TEST_FILES -x --tb=short 2>&1 || true)
        if echo "$TEST_OUTPUT" | grep -q "passed"; then
          TEST_RESULT="PASS"
        else
          TEST_RESULT="FAIL"
        fi
      fi
    } || TEST_RESULT="TEST_PATCH_FAILED"
  fi
} || TEST_RESULT="CLAUDE_PATCH_FAILED"

echo ""
echo "=== Analysis ==="
echo "  Test result: $TEST_RESULT"
echo "  Files match gold: $FILES_MATCH"
echo "  Extra files touched: ${EXTRA_FILES:-none}"
echo "  Missed files: ${MISSED_FILES:-none}"
echo "  Patch size: Claude=$CLAUDE_LINES vs Gold=$GOLD_LINES (ratio=$SIZE_RATIO)"
echo "  Duration: ${DURATION}s | Cost: \$${COST}"

# 5. Build structured result
jq -cn \
  --arg id "$INSTANCE_ID" \
  --arg repo "$REPO" \
  --arg model "$MODEL" \
  --arg test_result "$TEST_RESULT" \
  --arg files_match "$FILES_MATCH" \
  --arg extra_files "${EXTRA_FILES:-}" \
  --arg missed_files "${MISSED_FILES:-}" \
  --argjson gold_lines "$GOLD_LINES" \
  --argjson claude_lines "$CLAUDE_LINES" \
  --arg size_ratio "$SIZE_RATIO" \
  --argjson duration "$DURATION" \
  --argjson cost "${COST:-0}" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    instance_id: $id,
    repo: $repo,
    model: $model,
    test_result: $test_result,
    files_match: ($files_match == "true"),
    extra_files_touched: ($extra_files | split("\n") | map(select(length > 0))),
    missed_files: ($missed_files | split("\n") | map(select(length > 0))),
    gold_patch_lines: $gold_lines,
    claude_patch_lines: $claude_lines,
    size_ratio: ($size_ratio | tonumber),
    duration_seconds: $duration,
    cost_usd: $cost,
    timestamp: $timestamp
  }' > "${RESULT_PREFIX}-result.json"

echo ""
echo "Results saved to ${RESULT_PREFIX}-*.{json,patch}"
```

#### 1.3 Deviation analyser

Create `tests/golden/analyse-deviations.sh`:

This is the key script. It reads all golden test results and classifies deviations into behavioral categories.

```bash
#!/usr/bin/env bash
# Analyse deviations between Claude patches and gold patches
# Identifies behavioral anti-patterns and guardrail gaps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
REPORT_FILE="$RESULTS_DIR/deviation-report-$(date +%Y%m%d-%H%M%S).md"
GAPS_FILE="$RESULTS_DIR/guardrail-gaps.jsonl"

echo "=== Deviation Analysis ==="
echo ""

# Counters
TOTAL=0
TESTS_PASS=0
TESTS_FAIL=0
NO_PATCH=0
OVER_MODIFIED=0
UNDER_MODIFIED=0
BLOATED=0

# Behavioral categories
declare -A BEHAVIORS
BEHAVIORS=(
  ["over_modification"]=0      # Touched files the gold didn't
  ["under_modification"]=0     # Missed files the gold touched
  ["bloat"]=0                  # Claude's patch 1.5x+ larger than gold
  ["minimalism_fail"]=0        # Claude's patch much larger despite same files
  ["wrong_files"]=0            # Different files entirely
  ["test_pass_wrong_files"]=0  # Tests pass but wrong files touched (DANGEROUS)
  ["no_output"]=0              # Claude produced nothing
  ["correct"]=0                # Tests pass AND files match
)

# Process each result
for result_file in "$RESULTS_DIR"/*-result.json; do
  [ ! -f "$result_file" ] && continue
  TOTAL=$((TOTAL + 1))

  id=$(jq -r '.instance_id' "$result_file")
  model=$(jq -r '.model' "$result_file")
  test_result=$(jq -r '.test_result' "$result_file")
  files_match=$(jq -r '.files_match' "$result_file")
  extra_files=$(jq -r '.extra_files_touched | length' "$result_file")
  missed_files=$(jq -r '.missed_files | length' "$result_file")
  size_ratio=$(jq -r '.size_ratio' "$result_file")

  # Classify
  if [ "$test_result" = "NO_PATCH" ]; then
    BEHAVIORS["no_output"]=$((${BEHAVIORS["no_output"]} + 1))
    echo "  $id [$model]: NO_PATCH"
    continue
  fi

  if [ "$test_result" = "PASS" ] && [ "$files_match" = "true" ]; then
    BEHAVIORS["correct"]=$((${BEHAVIORS["correct"]} + 1))
    TESTS_PASS=$((TESTS_PASS + 1))

    # Still check for bloat
    if [ "$(awk "BEGIN {print ($size_ratio > 1.5)}")" = "1" ]; then
      BEHAVIORS["bloat"]=$((${BEHAVIORS["bloat"]} + 1))
      echo "  $id [$model]: PASS but BLOATED (${size_ratio}x gold size)"

      # Log as guardrail gap
      jq -cn --arg id "$id" --arg model "$model" --arg category "bloat" \
        --arg detail "Patch is ${size_ratio}x the gold patch size. Correct but over-engineered." \
        --arg hook_needed "verify-minimal-patch" \
        '{instance_id:$id, model:$model, category:$category, detail:$detail, suggested_hook:$hook_needed}' \
        >> "$GAPS_FILE"
    else
      echo "  $id [$model]: CORRECT"
    fi
    continue
  fi

  if [ "$test_result" = "PASS" ] && [ "$files_match" = "false" ]; then
    BEHAVIORS["test_pass_wrong_files"]=$((${BEHAVIORS["test_pass_wrong_files"]} + 1))
    TESTS_PASS=$((TESTS_PASS + 1))
    echo "  $id [$model]: PASS but WRONG FILES (tests pass, different files touched)"

    jq -cn --arg id "$id" --arg model "$model" --arg category "wrong_scope" \
      --arg detail "Tests pass but Claude modified different files than the gold patch." \
      --arg hook_needed "verify-change-scope" \
      '{instance_id:$id, model:$model, category:$category, detail:$detail, suggested_hook:$hook_needed}' \
      >> "$GAPS_FILE"
    continue
  fi

  if [ "$test_result" = "FAIL" ]; then
    TESTS_FAIL=$((TESTS_FAIL + 1))

    if [ "$extra_files" -gt 0 ]; then
      BEHAVIORS["over_modification"]=$((${BEHAVIORS["over_modification"]} + 1))
      echo "  $id [$model]: FAIL + OVER_MODIFIED ($extra_files extra files)"

      jq -cn --arg id "$id" --arg model "$model" --arg category "over_modification" \
        --arg detail "Claude touched $extra_files files beyond the gold patch scope." \
        --arg hook_needed "warn-scope-creep" \
        '{instance_id:$id, model:$model, category:$category, detail:$detail, suggested_hook:$hook_needed}' \
        >> "$GAPS_FILE"
    fi

    if [ "$missed_files" -gt 0 ]; then
      BEHAVIORS["under_modification"]=$((${BEHAVIORS["under_modification"]} + 1))
      echo "  $id [$model]: FAIL + UNDER_MODIFIED ($missed_files files missed)"

      jq -cn --arg id "$id" --arg model "$model" --arg category "under_modification" \
        --arg detail "Claude missed $missed_files files that the gold patch modified." \
        --arg hook_needed "verify-completeness" \
        '{instance_id:$id, model:$model, category:$category, detail:$detail, suggested_hook:$hook_needed}' \
        >> "$GAPS_FILE"
    fi

    if [ "$(awk "BEGIN {print ($size_ratio > 2.0)}")" = "1" ]; then
      BEHAVIORS["bloat"]=$((${BEHAVIORS["bloat"]} + 1))
      echo "  $id [$model]: FAIL + BLOATED (${size_ratio}x)"

      jq -cn --arg id "$id" --arg model "$model" --arg category "bloat" \
        --arg detail "Failed AND over-engineered at ${size_ratio}x gold size." \
        --arg hook_needed "warn-patch-bloat" \
        '{instance_id:$id, model:$model, category:$category, detail:$detail, suggested_hook:$hook_needed}' \
        >> "$GAPS_FILE"
    fi
  fi
done

echo ""
echo "=== Summary ==="
echo "Total tasks: $TOTAL"
echo "Tests pass: $TESTS_PASS"
echo "Tests fail: $TESTS_FAIL"
echo ""
echo "Behavioral categories:"
for key in "${!BEHAVIORS[@]}"; do
  echo "  $key: ${BEHAVIORS[$key]}"
done

echo ""
echo "Guardrail gaps logged to: $GAPS_FILE"
if [ -f "$GAPS_FILE" ]; then
  echo ""
  echo "=== Suggested New Hooks ==="
  jq -r '.suggested_hook' "$GAPS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count hook; do
    echo "  $hook: $count instances"
  done
fi

# Write markdown report
cat > "$REPORT_FILE" <<EOF
---
title: "Golden Reference Deviation Report"
created: "$(date +%Y-%m-%d)"
modified: "$(date +%Y-%m-%d)"
version: "1.0.0"
status: "active"
category: "report"
auto_generated: true
---

# Deviation Report

**Date:** $(date +%Y-%m-%d)
**Tasks analysed:** $TOTAL
**Tests passing:** $TESTS_PASS / $TOTAL

## Behavioral Breakdown

| Category | Count | Description |
|----------|-------|-------------|
| correct | ${BEHAVIORS["correct"]} | Tests pass, same files as gold |
| test_pass_wrong_files | ${BEHAVIORS["test_pass_wrong_files"]} | Tests pass but different files (dangerous) |
| over_modification | ${BEHAVIORS["over_modification"]} | Touched files beyond gold scope |
| under_modification | ${BEHAVIORS["under_modification"]} | Missed files the gold touched |
| bloat | ${BEHAVIORS["bloat"]} | Patch significantly larger than gold |
| no_output | ${BEHAVIORS["no_output"]} | Claude produced no changes |

## Guardrail Gap Analysis

$(if [ -f "$GAPS_FILE" ]; then
  echo "| Suggested Hook | Instances | Category |"
  echo "|---|---|---|"
  jq -r '[.suggested_hook, .category] | join("|")' "$GAPS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count rest; do
    hook=$(echo "$rest" | cut -d'|' -f1)
    cat=$(echo "$rest" | cut -d'|' -f2)
    echo "| $hook | $count | $cat |"
  done
fi)

## Per-Model Comparison

$(for model in haiku sonnet opus; do
  m_total=$(jq -r "select(.model==\"$model\") | .instance_id" "$RESULTS_DIR"/*-result.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$m_total" -eq 0 ] && continue
  m_pass=$(jq -r "select(.model==\"$model\" and .test_result==\"PASS\") | .instance_id" "$RESULTS_DIR"/*-result.json 2>/dev/null | wc -l | tr -d ' ')
  echo "**$model:** $m_pass / $m_total passing"
  echo ""
done)

*Auto-generated by claudetools golden reference analyser.*
EOF

echo "Report saved to: $REPORT_FILE"
```

### Phase 2: Run the pipeline

Create `tests/golden/run-golden-tests.sh`:

```bash
#!/usr/bin/env bash
# Full golden reference test pipeline
# Usage: run-golden-tests.sh [--model MODEL] [--count N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
MODEL="${1:-haiku}"
COUNT="${2:-10}"

# Ensure tasks exist
if [ ! -d "$TASKS_DIR" ] || [ -z "$(ls "$TASKS_DIR"/*.json 2>/dev/null)" ]; then
  echo "No tasks found. Running setup..."
  bash "$SCRIPT_DIR/setup-swebench.sh"
fi

echo "Running $COUNT golden reference tests with $MODEL..."
echo ""

DONE=0
for task_file in "$TASKS_DIR"/*.json; do
  [ ! -f "$task_file" ] && continue
  [ "$DONE" -ge "$COUNT" ] && break

  bash "$SCRIPT_DIR/golden-runner.sh" "$task_file" --model "$MODEL" || true
  echo ""
  DONE=$((DONE + 1))
done

echo "=== Running deviation analysis ==="
bash "$SCRIPT_DIR/analyse-deviations.sh"
```

### Phase 3: Update /train skill

Add to `skills/train/SKILL.md`:

```markdown
### /train golden
Run golden reference tests against SWE-bench tasks.
Compares Claude's output against known-correct human patches.
Identifies behavioral anti-patterns and guardrail gaps.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh haiku 10
```
First run downloads SWE-bench data (~2 min).
Each task clones a real GitHub repo, runs Claude headless, diffs against gold.
Estimated cost: ~$0.50-2.00 for 10 tasks with haiku.

### /train golden-cross-model
Run same golden tasks across all models to compare behavioral patterns.
```bash
for model in haiku sonnet opus; do
  bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/run-golden-tests.sh $model 10
done
bash ${CLAUDE_PLUGIN_ROOT}/tests/golden/analyse-deviations.sh
```
```

---

## What the Output Tells You

After a run, `guardrail-gaps.jsonl` contains entries like:

```json
{"instance_id":"django__django-15320","model":"haiku","category":"over_modification","detail":"Claude touched 3 files beyond the gold patch scope.","suggested_hook":"warn-scope-creep"}
{"instance_id":"flask__flask-4992","model":"haiku","category":"bloat","detail":"Patch is 3.40x the gold patch size. Correct but over-engineered.","suggested_hook":"verify-minimal-patch"}
{"instance_id":"scikit-learn__scikit-learn-25570","model":"sonnet","category":"wrong_scope","detail":"Tests pass but Claude modified different files than the gold patch.","suggested_hook":"verify-change-scope"}
```

When you see the same `suggested_hook` appearing across multiple tasks and models, that's a real guardrail that needs building. For example, if `warn-scope-creep` appears 8 times out of 30 tasks, that means Claude routinely modifies files it shouldn't - and no current hook catches it.

## Behavioral Categories Explained

| Category | What It Means | Why It Matters | Potential Hook |
|---|---|---|---|
| `over_modification` | Claude edited files the gold didn't touch | Scope creep - changes more than necessary | PostToolUse: warn when editing files not mentioned in task |
| `under_modification` | Claude missed files the gold edited | Incomplete fix - didn't follow the full chain | TaskCompleted: check if all relevant files were addressed |
| `bloat` | Claude's patch 1.5x+ larger than gold | Over-engineering, unnecessary abstraction | PostToolUse: warn when patch is disproportionately large |
| `wrong_scope` | Tests pass but different files | Correct outcome via wrong path (fragile) | PostToolUse: flag when fix location differs from conventional location |
| `test_pass_wrong_files` | Tests pass, wrong approach | Most dangerous - looks correct but isn't | Needs cross-model verification hook |
| `no_output` | Claude made no changes | Failed to engage with the task | SessionEnd: warn if no edits were made |

## What NOT to Build (Yet)

- Don't build the suggested hooks automatically. The deviation report is for YOU to review and decide which patterns warrant new hooks.
- Don't try to run the full SWE-bench evaluation harness (Docker-based, complex). The simple git-diff approach above is sufficient for guardrail discovery.
- Don't use AI to judge whether deviations are "good" or "bad". The mechanical diff against gold plus test pass/fail is the ground truth. Human review of the gap report decides what becomes a hook.

---

## Prerequisites

```bash
pip install datasets  # For HuggingFace dataset download
```

Git must be available (it is in Claude Code).

The `claude` CLI must be on PATH and functional for headless execution.

---

## Execution Order

1. Create directory structure: `tests/golden/{data,tasks,results}/`
2. Create `setup-swebench.sh`
3. Create `golden-runner.sh` (make executable)
4. Create `analyse-deviations.sh` (make executable)
5. Create `run-golden-tests.sh` (make executable)
6. Update `skills/train/SKILL.md`
7. Run setup: `bash tests/golden/setup-swebench.sh`
8. Test with one task: `bash tests/golden/golden-runner.sh tests/golden/tasks/<first-task>.json --model haiku`
9. Run 10 tasks: `bash tests/golden/run-golden-tests.sh haiku 10`
10. Review the deviation report and guardrail gaps
11. Commit and push
