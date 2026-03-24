# Golden Reference Testing - Bug Fixes

Read and fix the following bugs in `tests/golden/`. All fixes are small and surgical.

## Fix 1 - CRITICAL: $TASKS_DIR not interpolated in Python heredoc

**File:** `tests/golden/setup-swebench.sh`
**Line:** 36 (the `os.path.join('$TASKS_DIR', ...)` line)

**Problem:** The Python code uses `'$TASKS_DIR'` in single quotes. Python receives the literal string `$TASKS_DIR` instead of the actual resolved path. No task files get created. The entire pipeline is dead.

**Fix:** Replace:
```python
    with open(os.path.join('$TASKS_DIR', f'{fname}.json'), 'w') as f:
```
With:
```python
    tasks_dir = os.environ.get('TASKS_DIR', '.')
    with open(os.path.join(tasks_dir, f'{fname}.json'), 'w') as f:
```

And add `export TASKS_DIR` before the python3 call so it's available in the environment:
```bash
export TASKS_DIR
export DATA_DIR
```

## Fix 2 - MEDIUM: Missing mkdir -p in analyse-deviations.sh

**File:** `tests/golden/analyse-deviations.sh`
**Line:** 33 (the `> "$GAPS_FILE"` line)

**Problem:** If the results directory doesn't exist yet, writing to `$GAPS_FILE` fails silently. Same bug pattern as the headless-runner workspace issue.

**Fix:** Add before `> "$GAPS_FILE"`:
```bash
mkdir -p "$RESULTS_DIR" || { echo "ERROR: Cannot create $RESULTS_DIR" >&2; exit 1; }
```

## Fix 3 - MEDIUM: Unquoted $TEST_FILES in pytest command

**File:** `tests/golden/golden-runner.sh`
**Line:** ~149 (the `python -m pytest $TEST_FILES` line)

**Problem:** `$TEST_FILES` is unquoted. If any test filename contains spaces or glob characters, the command breaks due to word splitting.

**Fix:** Quote it properly. Replace:
```bash
TEST_OUTPUT=$(timeout 120 python -m pytest $TEST_FILES -x --tb=short 2>&1 || true)
```
With:
```bash
# shellcheck disable=SC2086
TEST_OUTPUT=$(timeout 120 python -m pytest $TEST_FILES -x --tb=short 2>&1 || true)
```

Actually, `$TEST_FILES` here is intentionally unquoted because pytest needs each file as a separate argument. Add the shellcheck disable comment and also validate the input:
```bash
if [ -n "$TEST_FILES" ] && echo "$TEST_FILES" | grep -q '[a-zA-Z]'; then
  # shellcheck disable=SC2086 -- intentional word splitting for pytest args
  TEST_OUTPUT=$(timeout 120 python -m pytest $TEST_FILES -x --tb=short 2>&1 || true)
```

## Fix 4 - MEDIUM: Add dependency checks to all scripts

Add a shared dependency check at the top of `run-golden-tests.sh` (the entry point):

```bash
# Dependency checks
for cmd in jq git python3 claude; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required but not installed" >&2; exit 1; }
done

# Check Python packages
python3 -c "import datasets" 2>/dev/null || { echo "ERROR: Python 'datasets' package required. Run: pip install datasets" >&2; exit 1; }
```

## Fix 5 - MINOR: Remove unused category counters

**File:** `tests/golden/analyse-deviations.sh`

The `minimalism_fail` and `wrong_files` categories are declared but never incremented. Either remove them or add classification logic that uses them. Preference: add logic, since `wrong_files` maps to a real behavioral category from the spec.

## Verification

After applying all fixes, run:
```bash
bash -n tests/golden/setup-swebench.sh
bash -n tests/golden/golden-runner.sh
bash -n tests/golden/analyse-deviations.sh
bash -n tests/golden/run-golden-tests.sh
```

All must pass syntax check with no output.

Then commit and push.
