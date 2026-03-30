# Phase 4: Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the TodoWrite dual-track, delete compensatory validators that Phase 2's skill constraints make redundant, and split memory tables into a dedicated database.

**Architecture:** Remove the TodoWrite PostToolUse hook and its JS handler. Delete 5 validators whose jobs are now handled by upstream skill workflows. Move memory-related tables from metrics.db to a separate memory.db for cleaner separation.

**Tech Stack:** Bash, JSON (hooks.json), SQLite schema

**Prerequisite:** Phase 2 (skills as constraints) should be deployed and running for at least 1 week. Collect validator trigger rates before deleting — only delete validators with near-zero trigger rate post-Phase 2.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/hooks/hooks.json` | Modify: remove TodoWrite hook entry |
| `plugin/scripts/on-todo-write.js` | Delete: TodoWrite handler |
| `plugin/scripts/lib/task-store.js` | Keep: still used by task-system MCP server |
| `plugin/scripts/lib/task-history.js` | Keep: still used by task-system MCP server |
| `plugin/scripts/validators/blind-edit.sh` | Delete: read-before-write enforced by skill workflows |
| `plugin/scripts/validators/task-scope.sh` | Delete: scope enforced by planning skill |
| `plugin/scripts/validators/unasked-deps.sh` | Delete: deps approved in planning skill |
| `plugin/scripts/validators/prefer-edit-over-write.sh` | Delete: tool routing in skill instructions |
| `plugin/scripts/validators/bulk-edit.sh` | Delete: workflow guidance, not safety |
| `plugin/scripts/pre-edit-gate.sh` | Modify: remove sourcing of deleted validators |
| `plugin/scripts/post-bash-gate.sh` | Modify: remove sourcing of unasked-deps validator |
| `plugin/scripts/lib/ensure-db.sh` | Modify: move memory tables to separate init function |

---

### Task 1: Remove TodoWrite hook and handler

**Files:**
- Modify: `plugin/hooks/hooks.json` (remove TodoWrite matcher block)
- Delete: `plugin/scripts/on-todo-write.js`

- [ ] **Step 1: Read the TodoWrite hook entry in hooks.json**

Run: `grep -n -A 8 'TodoWrite' plugin/hooks/hooks.json`
Expected: A matcher block around lines 116-123 with `on-todo-write.js`

- [ ] **Step 2: Remove the TodoWrite matcher block from hooks.json**

Delete the entire block:
```json
      {
        "matcher": "TodoWrite",
        "hooks": [
          {
            "type": "command",
            "command": "node ${CLAUDE_PLUGIN_ROOT}/scripts/on-todo-write.js",
            "timeout": 5
          }
        ]
      },
```

- [ ] **Step 3: Delete the handler**

```bash
rm plugin/scripts/on-todo-write.js
```

- [ ] **Step 4: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('plugin/hooks/hooks.json'))" && echo OK`
Expected: `OK`

- [ ] **Step 5: Verify no remaining references**

Run: `grep -r 'on-todo-write\|TodoWrite' plugin/scripts/ plugin/hooks/ --include='*.sh' --include='*.json' --include='*.js' | grep -v node_modules`
Expected: No matches (task-store.js and task-history.js should NOT reference TodoWrite directly)

- [ ] **Step 6: Commit**

```bash
git rm plugin/scripts/on-todo-write.js
git add plugin/hooks/hooks.json
git commit -m "chore: remove TodoWrite hook and handler

Native TaskCreate/TaskUpdate is the primary task tracking mechanism.
The TodoWrite → on-todo-write.js dual-track added complexity without
value. task-store.js and task-history.js remain for the MCP server."
```

---

### Task 2: Delete compensatory validators

**Prerequisite check:** Before executing this task, verify trigger rates from the past week. If any validator has >5% trigger rate post-Phase 2, keep it and skip deletion.

**Files:**
- Delete: `plugin/scripts/validators/blind-edit.sh`
- Delete: `plugin/scripts/validators/task-scope.sh`
- Delete: `plugin/scripts/validators/unasked-deps.sh`
- Delete: `plugin/scripts/validators/prefer-edit-over-write.sh`
- Delete: `plugin/scripts/validators/bulk-edit.sh`
- Modify: `plugin/scripts/pre-edit-gate.sh` (remove sourcing)
- Modify: `plugin/scripts/post-bash-gate.sh` (remove sourcing if unasked-deps is sourced there)

- [ ] **Step 1: Check which dispatchers source each validator**

Run:
```bash
for v in blind-edit task-scope unasked-deps prefer-edit-over-write bulk-edit; do
  echo "=== $v ==="
  grep -rn "$v" plugin/scripts/*.sh | grep -v validators/ | head -5
done
```

Note which dispatchers source each validator and which `run_validator` calls reference them.

- [ ] **Step 2: Remove validator sourcing and run_validator calls from dispatchers**

For each dispatcher that sources a deleted validator:
1. Remove the `source "$SCRIPT_DIR/validators/<name>.sh"` line
2. Remove the `run_validator "<name>" validate_<func>` line

- [ ] **Step 3: Delete the validator files**

```bash
rm plugin/scripts/validators/blind-edit.sh \
   plugin/scripts/validators/task-scope.sh \
   plugin/scripts/validators/unasked-deps.sh \
   plugin/scripts/validators/prefer-edit-over-write.sh \
   plugin/scripts/validators/bulk-edit.sh
```

- [ ] **Step 4: Verify syntax of modified dispatchers**

```bash
bash -n plugin/scripts/pre-edit-gate.sh && echo "pre-edit-gate: OK"
bash -n plugin/scripts/post-bash-gate.sh && echo "post-bash-gate: OK"
bash -n plugin/scripts/validate-content.sh && echo "validate-content: OK"
```

- [ ] **Step 5: Verify no broken references**

Run: `grep -r 'blind.edit\|task.scope\|unasked.deps\|prefer.edit\|bulk.edit' plugin/scripts/*.sh plugin/hooks/ | grep -v validators/ | grep -v '\.bak'`
Expected: No matches

- [ ] **Step 6: Commit**

```bash
git rm plugin/scripts/validators/blind-edit.sh \
       plugin/scripts/validators/task-scope.sh \
       plugin/scripts/validators/unasked-deps.sh \
       plugin/scripts/validators/prefer-edit-over-write.sh \
       plugin/scripts/validators/bulk-edit.sh
git add plugin/scripts/pre-edit-gate.sh plugin/scripts/post-bash-gate.sh
git commit -m "chore: remove 5 compensatory validators

These validators are now redundant — Phase 2 skill constraints prevent
the problems they were detecting:
- blind-edit: read-before-write in skill workflows
- task-scope: scope defined by planning skill acceptance criteria
- unasked-deps: dependencies approved in plan
- prefer-edit-over-write: tool routing in skill instructions
- bulk-edit: workflow guidance, not safety"
```

---

### Task 3: Split memory tables to separate init function

**Files:**
- Modify: `plugin/scripts/lib/ensure-db.sh`

- [ ] **Step 1: Read the memory table section**

Run: `sed -n '60,140p' plugin/scripts/lib/ensure-db.sh`
Note exact lines for: `memories`, `memories_fts`, `project_memories`, `memory_effectiveness` tables and FTS triggers.

- [ ] **Step 2: Extract memory tables into a separate function**

Add a new function `ensure_memory_db()` that:
1. Sets `MEMORY_DB` path (same directory as `METRICS_DB` but named `memory.db`)
2. Creates the 4 memory tables + FTS triggers in `$MEMORY_DB`
3. Remove these tables from `ensure_metrics_db()`

```bash
# After ensure_metrics_db() function, add:

ensure_memory_db() {
  local data_dir
  data_dir=$(dirname "$METRICS_DB")
  MEMORY_DB="${data_dir}/memory.db"
  export MEMORY_DB

  command -v sqlite3 &>/dev/null || return 0

  sqlite3 "$MEMORY_DB" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;" 2>/dev/null || true

  # memories table
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    type TEXT DEFAULT 'general',
    name TEXT,
    description TEXT,
    tags TEXT DEFAULT '',
    confidence REAL DEFAULT 0.5,
    access_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    last_accessed TEXT DEFAULT (datetime('now')),
    source TEXT DEFAULT 'session',
    file_path TEXT
  );" 2>/dev/null || true

  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_confidence ON memories(confidence DESC);" 2>/dev/null || true

  # FTS5 virtual table
  sqlite3 "$MEMORY_DB" "CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    name, description, content,
    content='memories',
    content_rowid='id',
    tokenize='porter unicode61'
  );" 2>/dev/null || true

  # FTS sync triggers
  sqlite3 "$MEMORY_DB" "
    CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
      INSERT INTO memories_fts(rowid, name, description, content) VALUES (new.id, new.name, new.description, new.content);
    END;
    CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, name, description, content) VALUES('delete', old.id, old.name, old.description, old.content);
    END;
    CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, name, description, content) VALUES('delete', old.id, old.name, old.description, old.content);
      INSERT INTO memories_fts(rowid, name, description, content) VALUES (new.id, new.name, new.description, new.content);
    END;
  " 2>/dev/null || true

  # project_memories table
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS project_memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    content TEXT NOT NULL,
    confidence REAL DEFAULT 0.5,
    times_reinforced INTEGER DEFAULT 1,
    times_contradicted INTEGER DEFAULT 0,
    first_seen TEXT DEFAULT (datetime('now')),
    last_seen TEXT DEFAULT (datetime('now')),
    project_type TEXT,
    source TEXT DEFAULT 'session'
  );" 2>/dev/null || true

  # memory_effectiveness table
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS memory_effectiveness (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id INTEGER,
    session_id TEXT,
    was_relevant INTEGER DEFAULT 0,
    timestamp TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE
  );" 2>/dev/null || true
}
```

- [ ] **Step 3: Remove memory tables from ensure_metrics_db()**

Delete the memories, memories_fts, project_memories, memory_effectiveness CREATE TABLE statements and triggers from `ensure_metrics_db()`.

- [ ] **Step 4: Update callers to also call ensure_memory_db()**

Run: `grep -rn 'ensure_metrics_db' plugin/scripts/ | grep -v lib/ensure-db.sh`
For each caller that also uses memory tables, add `ensure_memory_db` call after `ensure_metrics_db`.

- [ ] **Step 5: Verify syntax**

Run: `bash -n plugin/scripts/lib/ensure-db.sh && echo OK`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add plugin/scripts/lib/ensure-db.sh
git commit -m "refactor: split memory tables into separate memory.db

Memory tables (memories, memories_fts, project_memories,
memory_effectiveness) now live in memory.db instead of metrics.db.
Reduces contention and makes memory system independently testable."
```

---

## Self-Review

1. **Spec coverage:** ✓ Drop TodoWrite track (Task 1), ✓ Delete compensatory validators (Task 2), ✓ Split memory DB (Task 3)
2. **Placeholder scan:** No TBD/TODO found. Task 2 has a prerequisite check (trigger rate) which is a real gate, not a placeholder.
3. **Type consistency:** `MEMORY_DB` export follows `METRICS_DB` pattern. Validator deletion uses same `git rm` + dispatcher update pattern throughout.
