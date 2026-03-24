---
title: "Implementation Plan Update - Deploy, Reload and Train"
created: "2026-03-15"
modified: "2026-03-15"
version: "1.0.0"
status: "active"
category: "plan"
tags: ["implementation", "deployment", "training", "hot-reload"]
supersedes: ""
superseded_by: ""
author: "claude"
---

# Implementation Plan Update: Deploy, Reload, and Train

Your current plan is correct through Phase 11 but is missing the critical final phases. The entire point of building the testing and training infrastructure is to run it live against the plugin's own hooks. Building the code is not the end - deploying it and executing training is.

## What to change

After your current Phase 11 (Verify Everything), add the following phases. These are mandatory and the task is not complete without them.

---

### Phase 12: Commit, Push, and Publish

After all tests pass locally in Phase 11:

```bash
# 1. Stage all new and modified files
git add scripts/doc-manager.sh scripts/doc-index-generator.sh scripts/doc-stale-detector.sh
git add skills/docs-manager/ skills/train/
git add tests/
git add hooks/hooks.json
git add scripts/failure-pattern-detector.sh scripts/enforce-team-usage.sh

# 2. Commit with a clear message
git commit -m "feat: add documentation management, testing suite, and training infrastructure

- Fix 3 outstanding bugs (PPID, python3, redundant variable)
- Add doc-manager.sh, doc-index-generator.sh, doc-stale-detector.sh hooks
- Add /docs-manager skill (init, audit, archive, reindex)
- Add /train skill (test, code, noncode, edge, compare, all)
- Add BATS unit tests for all hooks including doc-manager
- Add safety command corpus (dangerous, safe, boundary)
- Add integration tests (self-learning pipeline, compaction, doc management)
- Add training scenarios (code, non-code, edge cases)
- Add training prompts for use with native /loop
- Add scaffold projects (node, python, rust, go, general)"

# 3. Push to GitHub
git push origin main
```

**Do not proceed to Phase 13 until the push succeeds.**

---

### Phase 13: Update and Hot Reload the Plugin

The plugin is installed from the marketplace. After pushing, you need to pull the latest version and reload it in the live session so the new hooks and skills are active.

```bash
# 1. Update the plugin to pull the latest from GitHub
claude plugin update owenob1/claude-code
```

Then hot reload so the new hooks and skills take effect without restarting:

```
/reload-plugins
```

**Verification after reload:**

1. Confirm the new hooks are loaded:
   ```bash
   # Check hooks.json includes the new doc hooks
   cat "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json" | jq '.hooks[] | select(.matcher | test("doc-manager|doc-index|doc-stale"))' 2>/dev/null
   ```

2. Confirm the new skills are available:
   ```bash
   ls "${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/SKILL.md" "${CLAUDE_PLUGIN_ROOT}/skills/train/SKILL.md"
   ```

3. Confirm the bug fixes are live:
   ```bash
   # PPID fix should be gone
   grep -c "PPID" "${CLAUDE_PLUGIN_ROOT}/scripts/failure-pattern-detector.sh"
   # Should return 0

   # python3 should be replaced with jq
   grep -c "python3" "${CLAUDE_PLUGIN_ROOT}/scripts/enforce-team-usage.sh"
   # Should return 0
   ```

**Do not proceed to Phase 14 until all verifications pass.**

---

### Phase 14: Execute Deterministic Tests Live

Now that the plugin is live, run the deterministic test suite through the actual installed plugin (not the dev copy):

```bash
# Run full BATS suite
/train test
```

This runs:
- All BATS unit tests
- Self-learning pipeline integration test
- Safety corpus accuracy test (FP < 2%, FN = 0%)
- Documentation management integration test

**All tests must pass.** If any fail, fix the issue, commit, push, update plugin, reload, and re-run. Do not proceed until green.

---

### Phase 15: Execute Training Suite Live

With the plugin live and deterministic tests passing, run the agent-driven training:

```bash
# 1. Run one of each scenario type to establish baseline metrics
/train code
/train noncode
/train edge

# 2. Check that metrics.db is being populated
sqlite3 "${CLAUDE_PLUGIN_ROOT}/scripts/data/metrics.db" "SELECT COUNT(*) FROM tool_outcomes;"
sqlite3 "${CLAUDE_PLUGIN_ROOT}/scripts/data/metrics.db" "SELECT COUNT(*) FROM session_metrics;"

# 3. Set up continuous training via /loop
/loop 30m /train code
/loop 1h /train noncode
/loop 2h /train test
```

After the first few training iterations complete:

```bash
# 4. Review training results
cat tests/training/results/training-log.jsonl | tail -5

# 5. Generate a training report
bash tests/training/report.sh
```

---

### Phase 16: Verify Self-Learning Pipeline End-to-End

This is the final verification that the entire system works as designed. The self-learning pipeline should now have real data flowing through it:

1. **Capture** - Confirm tool_outcomes has entries from the training runs:
   ```bash
   sqlite3 "${CLAUDE_PLUGIN_ROOT}/scripts/data/metrics.db" \
     "SELECT tool_name, COUNT(*), AVG(success) FROM tool_outcomes GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 10;"
   ```

2. **Aggregate** - Trigger a session aggregation and confirm session_metrics updates:
   ```bash
   sqlite3 "${CLAUDE_PLUGIN_ROOT}/scripts/data/metrics.db" \
     "SELECT session_id, total_tool_calls, total_failures FROM session_metrics ORDER BY created_at DESC LIMIT 5;"
   ```

3. **Inject** - Start a new session context and verify dynamic-rules.sh injects the threshold data and recent failures into the prompt.

4. **Tune** - If 5+ training iterations have completed, run threshold analysis and verify threshold_overrides table has been updated:
   ```bash
   sqlite3 "${CLAUDE_PLUGIN_ROOT}/scripts/data/metrics.db" \
     "SELECT * FROM threshold_overrides;"
   ```

5. **Documentation hooks** - Create a test .md file and verify:
   - doc-manager.sh enforces naming and front matter
   - doc-index-generator.sh updates the index at session end
   - doc-stale-detector.sh flags issues at session start

---

## Summary of Changes to Your Plan

| Current Plan | What's Missing |
|---|---|
| Phases 0-11: Build and verify locally | Correct, keep as-is |
| (nothing) | Phase 12: Commit, push to GitHub |
| (nothing) | Phase 13: Update plugin + `/reload-plugins` |
| (nothing) | Phase 14: Run `/train test` live |
| (nothing) | Phase 15: Run training scenarios live + set up `/loop` |
| (nothing) | Phase 16: Verify self-learning pipeline has real data flowing |

The task is complete when the plugin is deployed, live, tested, and actively training - not when the code is written.
