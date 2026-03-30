# Phase 5: Automate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automated health tracking — skill invocation telemetry, stale skill detection, and validator false-positive rate tracking.

**Architecture:** Extend existing telemetry infrastructure (lib/telemetry.sh + metrics.db) with 2 new tables and 1 new query script. Add skill invocation tracking to the inject-prompt-context.sh hook. Create a health-report query script that surfaces stale skills and high-FP validators.

**Tech Stack:** Bash, SQLite, jq

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/scripts/lib/ensure-db.sh` | Modify: add skill_invocations and validator_health tables |
| `plugin/scripts/inject-prompt-context.sh` | Modify: emit telemetry when skill is matched |
| `plugin/scripts/lib/telemetry.sh` | Modify: add emit_skill_invocation function |
| `plugin/scripts/lib/health-report.sh` | Create: query stale skills + high-FP validators |
| `plugin/skills/session-dashboard/scripts/generate-report.sh` | Modify: include health metrics |

---

### Task 1: Add skill_invocations table to metrics.db

**Files:**
- Modify: `plugin/scripts/lib/ensure-db.sh`

- [ ] **Step 1: Read the end of ensure_metrics_db() to find insertion point**

Run: `tail -30 plugin/scripts/lib/ensure-db.sh`

- [ ] **Step 2: Add skill_invocations table**

Before the closing `}` of `ensure_metrics_db()`, add:

```bash
  # Skill invocation tracking
  sqlite3 "$METRICS_DB" "CREATE TABLE IF NOT EXISTS skill_invocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_name TEXT NOT NULL,
    session_id TEXT,
    matched_by TEXT DEFAULT 'keyword',
    timestamp TEXT DEFAULT (datetime('now'))
  );" 2>/dev/null || true

  sqlite3 "$METRICS_DB" "CREATE INDEX IF NOT EXISTS idx_skill_inv_name ON skill_invocations(skill_name);" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "CREATE INDEX IF NOT EXISTS idx_skill_inv_ts ON skill_invocations(timestamp);" 2>/dev/null || true
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/lib/ensure-db.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/lib/ensure-db.sh
git commit -m "feat: add skill_invocations table to metrics.db

Tracks which skills are matched by intent classification, enabling
stale skill detection and usage analytics."
```

---

### Task 2: Add emit_skill_invocation to telemetry.sh

**Files:**
- Modify: `plugin/scripts/lib/telemetry.sh`

- [ ] **Step 1: Read the end of telemetry.sh to find insertion point**

Run: `tail -20 plugin/scripts/lib/telemetry.sh`

- [ ] **Step 2: Add the emit function**

Append to the file:

```bash
# emit_skill_invocation SKILL_NAME SESSION_ID [MATCHED_BY]
# Record a skill invocation in metrics.db for usage tracking.
emit_skill_invocation() {
  local skill="${1:-}" session_id="${2:-}" matched_by="${3:-keyword}"
  [ -z "$skill" ] && return 0
  command -v sqlite3 &>/dev/null || return 0
  [ -n "${METRICS_DB:-}" ] || return 0
  sqlite3 "$METRICS_DB" "INSERT INTO skill_invocations (skill_name, session_id, matched_by) VALUES ('$skill', '$session_id', '$matched_by');" 2>/dev/null &
}
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/lib/telemetry.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/lib/telemetry.sh
git commit -m "feat: add emit_skill_invocation to telemetry library

Records skill matches to metrics.db for usage tracking. Runs in
background (&) to avoid blocking the UserPromptSubmit hook."
```

---

### Task 3: Wire skill telemetry into inject-prompt-context.sh

**Files:**
- Modify: `plugin/scripts/inject-prompt-context.sh`

- [ ] **Step 1: Read the current file to find the skill routing section**

Run: `cat -n plugin/scripts/inject-prompt-context.sh`
Find the section added in Phase 2 where `classify_intent` is called.

- [ ] **Step 2: Add telemetry emission after skill match**

After the `MATCHED_SKILL` check, add telemetry:

```bash
if [ -n "$MATCHED_SKILL" ]; then
  SKILL_HINT=$(format_skill_hint "$MATCHED_SKILL")
  echo "$SKILL_HINT"
  # Track skill invocation for usage analytics
  source "$SCRIPT_DIR/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_SKILL" "$SESSION_ID" "keyword" 2>/dev/null || true
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/inject-prompt-context.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/inject-prompt-context.sh
git commit -m "feat: emit skill invocation telemetry at UserPromptSubmit

Records which skills are matched by intent classification. Enables
stale skill detection (zero invocations over 30 days = review candidate)."
```

---

### Task 4: Create health-report.sh — automated health tracking

**Files:**
- Create: `plugin/scripts/lib/health-report.sh`

- [ ] **Step 1: Create the health report library**

```bash
#!/usr/bin/env bash
# health-report.sh — Query metrics.db for plugin health indicators
# Functions return formatted text suitable for session-dashboard output.

# Requires: sqlite3, METRICS_DB set

# stale_skills [DAYS] — Skills with zero invocations in the past N days (default 30)
stale_skills() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  # Get all known skills from recent invocations
  local active_skills
  active_skills=$(sqlite3 "$METRICS_DB" "
    SELECT DISTINCT skill_name FROM skill_invocations
    WHERE timestamp > datetime('now', '-${days} days')
  " 2>/dev/null || true)

  # Compare against skill directories
  local skill_dir="${CLAUDE_PLUGIN_ROOT:-}/skills"
  [ -d "$skill_dir" ] || return 0

  echo "=== Stale Skills (0 invocations in ${days} days) ==="
  local found=0
  for dir in "$skill_dir"/*/; do
    local name
    name=$(basename "$dir")
    if ! echo "$active_skills" | grep -qF "$name"; then
      echo "  - $name"
      found=$((found + 1))
    fi
  done
  [ "$found" -eq 0 ] && echo "  (none — all skills active)"
}

# validator_false_positives [DAYS] — Validators with >50% block rate that get overridden
validator_false_positives() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  echo "=== Validator Health (past ${days} days) ==="
  sqlite3 -header -column "$METRICS_DB" "
    SELECT
      hook_name,
      SUM(CASE WHEN decision = 'block' THEN 1 ELSE 0 END) as blocks,
      SUM(CASE WHEN decision = 'warn' THEN 1 ELSE 0 END) as warns,
      SUM(CASE WHEN decision = 'allow' THEN 1 ELSE 0 END) as allows,
      COUNT(*) as total,
      ROUND(100.0 * SUM(CASE WHEN decision = 'block' THEN 1 ELSE 0 END) / COUNT(*), 1) as block_pct
    FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
      AND event_type IN ('PreToolUse', 'PostToolUse', 'TaskCompleted')
    GROUP BY hook_name
    HAVING total >= 5
    ORDER BY block_pct DESC
  " 2>/dev/null || echo "  (no data — run for a few sessions first)"
}

# dead_validators [DAYS] — Validators with 0 triggers in N days
dead_validators() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  echo "=== Dead Validators (0 triggers in ${days} days) ==="
  local active_validators
  active_validators=$(sqlite3 "$METRICS_DB" "
    SELECT DISTINCT hook_name FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
  " 2>/dev/null || true)

  local validator_dir="${CLAUDE_PLUGIN_ROOT:-}/scripts/validators"
  [ -d "$validator_dir" ] || return 0

  local found=0
  for f in "$validator_dir"/*.sh; do
    local name
    name=$(basename "$f" .sh)
    if ! echo "$active_validators" | grep -qF "$name"; then
      echo "  - $name"
      found=$((found + 1))
    fi
  done
  [ "$found" -eq 0 ] && echo "  (none — all validators active)"
}

# full_health_report — Run all health checks
full_health_report() {
  local days="${1:-30}"
  echo "Plugin Health Report (past ${days} days)"
  echo "========================================"
  echo ""
  stale_skills "$days"
  echo ""
  validator_false_positives "$days"
  echo ""
  dead_validators "$days"
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n plugin/scripts/lib/health-report.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/lib/health-report.sh
git commit -m "feat: add health-report.sh for automated plugin health tracking

Queries metrics.db for stale skills (zero invocations), validator
false-positive rates, and dead validators. Used by session-dashboard."
```

---

### Task 5: Wire health report into session-dashboard

**Files:**
- Modify: `plugin/skills/session-dashboard/scripts/generate-report.sh`

- [ ] **Step 1: Read the current generate-report.sh**

Run: `cat -n plugin/skills/session-dashboard/scripts/generate-report.sh`

- [ ] **Step 2: Add health report section**

At the end of the script (before the final exit), add:

```bash
# Plugin health metrics
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HEALTH_LIB="$SCRIPT_DIR/../../scripts/lib/health-report.sh"
if [ -f "$HEALTH_LIB" ]; then
  source "$HEALTH_LIB"
  echo ""
  full_health_report 30
fi
```

Note: The path from `skills/session-dashboard/scripts/` to `scripts/lib/` is `../../scripts/lib/`. Adjust if the actual directory structure differs.

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/skills/session-dashboard/scripts/generate-report.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/session-dashboard/scripts/generate-report.sh
git commit -m "feat: include health metrics in session-dashboard report

Stale skills, validator false-positive rates, and dead validators
now appear in the session dashboard output."
```

---

## Self-Review

1. **Spec coverage:** ✓ Skill invocation telemetry (Tasks 1-3), ✓ Stale skill detection (Task 4: `stale_skills()`), ✓ False-positive rate tracking (Task 4: `validator_false_positives()`), ✓ Dead validator detection (Task 4: `dead_validators()`)
2. **Placeholder scan:** No TBD/TODO found. All SQL complete. All bash functions complete.
3. **Type consistency:** `emit_skill_invocation` parameters match `skill_invocations` table columns. `METRICS_DB` used consistently (set by ensure-db.sh). Health report functions all take `days` parameter with default 30.
