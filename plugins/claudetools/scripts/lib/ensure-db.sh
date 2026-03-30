#!/usr/bin/env bash
# ensure-db.sh — Create metrics.db and memory.db with schema if missing
# Usage: source "$(dirname "$0")/lib/ensure-db.sh"

# DB path: prefer a stable location that survives plugin version upgrades.
# When CLAUDE_PLUGIN_ROOT is a versioned cache path (e.g. .../claudetools/3.7.3/),
# store the DB one level above the version directory so it persists across upgrades.
_plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [[ "$_plugin_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # Versioned install path — use parent directory (plugin name level) for stable DB
  _data_dir="$(dirname "$_plugin_root")/data"
else
  _data_dir="${_plugin_root}/data"
fi
METRICS_DB="${_data_dir}/metrics.db"
MEMORY_DB="${_data_dir}/memory.db"
export MEMORY_DB

ensure_metrics_db() {
  local db_dir
  db_dir=$(dirname "$METRICS_DB")
  [ -d "$db_dir" ] || mkdir -p "$db_dir" 2>/dev/null || true

  if [ ! -f "$METRICS_DB" ]; then
    sqlite3 "$METRICS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS tool_outcomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  tool_name TEXT NOT NULL,
  success INTEGER NOT NULL DEFAULT 1,
  duration_ms INTEGER,
  file_path TEXT,
  timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS session_metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  total_tool_calls INTEGER DEFAULT 0,
  total_failures INTEGER DEFAULT 0,
  total_edits INTEGER DEFAULT 0,
  unique_files_edited INTEGER DEFAULT 0,
  edit_churn_rate REAL DEFAULT 0.0,
  tasks_completed INTEGER DEFAULT 0,
  duration_minutes REAL DEFAULT 0.0,
  project_type TEXT DEFAULT 'general',
  timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS threshold_overrides (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  metric_name TEXT NOT NULL UNIQUE,
  default_value REAL NOT NULL,
  current_value REAL NOT NULL,
  min_bound REAL NOT NULL,
  max_bound REAL NOT NULL,
  last_updated TEXT NOT NULL DEFAULT (datetime('now')),
  reason TEXT
);

-- Seed default thresholds
INSERT OR IGNORE INTO threshold_overrides (metric_name, default_value, current_value, min_bound, max_bound, reason)
VALUES
  ('edit_frequency_limit', 3, 3, 1.5, 6, 'Default: warn after 3 edits to same file'),
  ('failure_loop_limit', 3, 3, 1.5, 6, 'Default: block after 3 same-tool failures');

CREATE INDEX IF NOT EXISTS idx_outcomes_session ON tool_outcomes(session_id);
CREATE INDEX IF NOT EXISTS idx_outcomes_tool ON tool_outcomes(tool_name);
CREATE INDEX IF NOT EXISTS idx_sessions_timestamp ON session_metrics(timestamp);

CREATE TABLE IF NOT EXISTS hook_outcomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  hook_name TEXT NOT NULL,
  event_type TEXT NOT NULL,
  decision TEXT NOT NULL,
  tool_name TEXT,
  is_correct INTEGER DEFAULT NULL,
  classification TEXT DEFAULT NULL,
  threshold_used REAL DEFAULT NULL,
  threshold_name TEXT DEFAULT NULL,
  model_family TEXT DEFAULT NULL,
  timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_hook_outcomes_hook ON hook_outcomes(hook_name);
CREATE INDEX IF NOT EXISTS idx_hook_outcomes_session ON hook_outcomes(session_id);

CREATE TABLE IF NOT EXISTS threshold_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  metric_name TEXT NOT NULL,
  old_value REAL NOT NULL,
  new_value REAL NOT NULL,
  trigger TEXT NOT NULL,
  precision_at_change REAL,
  recall_at_change REAL,
  cost_at_change REAL,
  learning_rate REAL,
  session_id TEXT,
  timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_thresh_hist_metric ON threshold_history(metric_name);

CREATE TABLE IF NOT EXISTS model_profiles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model_family TEXT NOT NULL,
  metric_name TEXT NOT NULL,
  multiplier REAL NOT NULL DEFAULT 1.0,
  last_updated TEXT NOT NULL DEFAULT (datetime('now')),
  reason TEXT,
  UNIQUE(model_family, metric_name)
);

INSERT OR IGNORE INTO model_profiles (model_family, metric_name, multiplier, reason)
VALUES
  ('opus', '*', 1.0, 'Baseline: most capable model'),
  ('sonnet', '*', 1.0, 'Default: same as opus'),
  ('haiku', '*', 0.85, 'Tighter defaults for less capable model');

INSERT OR IGNORE INTO threshold_overrides (metric_name, default_value, current_value, min_bound, max_bound, reason) VALUES
  ('diverse_failure_total_warn', 5, 5, 3, 10, 'failure-pattern-detector: warn after N diverse failures'),
  ('churn_warning', 2.0, 2.0, 1.0, 5.0, 'inject-session-context: avg churn rate trigger'),
  ('failure_warning', 10, 10, 5, 25, 'inject-session-context: recent failure count trigger'),
  ('memory_confidence_inject', 0.7, 0.7, 0.3, 0.95, 'inject-session-context: min confidence for memory injection'),
  ('memory_decay_rate', 0.95, 0.95, 0.8, 0.99, 'inject-session-context: per-period memory decay multiplier'),
  ('memory_decay_window_days', 30, 30, 7, 90, 'inject-session-context: days before decay kicks in'),
  ('memory_prune_threshold', 0.1, 0.1, 0.05, 0.3, 'inject-session-context: confidence below which unreinforced memories pruned'),
  ('ts_any_limit', 3, 3, 1, 8, 'verify-no-stubs: max :any uses before warning'),
  ('ts_as_any_limit', 2, 2, 1, 5, 'verify-no-stubs: max as any uses before warning'),
  ('ts_ignore_limit', 1, 1, 0, 3, 'verify-no-stubs: max @ts-ignore uses before warning'),
  ('uncommitted_file_limit', 5, 5, 2, 15, 'enforce-git-commits: modified file count before blocking'),
  ('large_change_threshold', 15, 15, 5, 50, 'session-stop-gate: files in commit before scope warning'),
  ('ai_audit_diff_threshold', 30, 30, 10, 100, 'session-stop-gate: diff lines before AI audit triggers'),
  ('outcome_retention_days', 90, 90, 30, 365, 'aggregate-session: days to keep tool_outcomes');
SQL
  fi

  # Migration: hook_outcomes table
  sqlite3 "$METRICS_DB" "CREATE TABLE IF NOT EXISTS hook_outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, hook_name TEXT NOT NULL,
    event_type TEXT NOT NULL, decision TEXT NOT NULL, tool_name TEXT, is_correct INTEGER DEFAULT NULL,
    classification TEXT DEFAULT NULL, threshold_used REAL DEFAULT NULL, threshold_name TEXT DEFAULT NULL,
    model_family TEXT DEFAULT NULL, timestamp TEXT NOT NULL DEFAULT (datetime('now')));" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "CREATE INDEX IF NOT EXISTS idx_hook_outcomes_hook ON hook_outcomes(hook_name);" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "CREATE INDEX IF NOT EXISTS idx_hook_outcomes_session ON hook_outcomes(session_id);" 2>/dev/null || true

  # Migration: threshold_history table
  sqlite3 "$METRICS_DB" "CREATE TABLE IF NOT EXISTS threshold_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT, metric_name TEXT NOT NULL, old_value REAL NOT NULL,
    new_value REAL NOT NULL, trigger TEXT NOT NULL, precision_at_change REAL, recall_at_change REAL,
    cost_at_change REAL, learning_rate REAL, session_id TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')));" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "CREATE INDEX IF NOT EXISTS idx_thresh_hist_metric ON threshold_history(metric_name);" 2>/dev/null || true

  # Migration: model_profiles table
  sqlite3 "$METRICS_DB" "CREATE TABLE IF NOT EXISTS model_profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT, model_family TEXT NOT NULL, metric_name TEXT NOT NULL,
    multiplier REAL NOT NULL DEFAULT 1.0, last_updated TEXT NOT NULL DEFAULT (datetime('now')),
    reason TEXT, UNIQUE(model_family, metric_name));" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "INSERT OR IGNORE INTO model_profiles (model_family, metric_name, multiplier, reason) VALUES
    ('opus', '*', 1.0, 'Baseline: most capable model'),
    ('sonnet', '*', 1.0, 'Default: same as opus'),
    ('haiku', '*', 0.85, 'Tighter defaults for less capable model');" 2>/dev/null || true

  # --- Training framework tables (removed from metrics.db) ---
  # These tables were never populated in production. If the safety-evaluator
  # skill needs them, it should create a separate training.db on demand.
  # Removed tables: reference_codebases, prompt_chains, chain_steps,
  # chain_executions, step_executions, deviations, guardrail_gaps
  # Original schema preserved in git history at this commit.

  # Migration: add step_execution_id to hook_outcomes if missing
  sqlite3 "$METRICS_DB" "ALTER TABLE hook_outcomes ADD COLUMN step_execution_id TEXT REFERENCES step_executions(step_execution_id);" 2>/dev/null || true

  # Migration: new threshold_overrides rows
  sqlite3 "$METRICS_DB" "INSERT OR IGNORE INTO threshold_overrides (metric_name, default_value, current_value, min_bound, max_bound, reason) VALUES
    ('diverse_failure_total_warn', 5, 5, 3, 10, 'failure-pattern-detector: warn after N diverse failures'),
    ('churn_warning', 2.0, 2.0, 1.0, 5.0, 'inject-session-context: avg churn rate trigger'),
    ('failure_warning', 10, 10, 5, 25, 'inject-session-context: recent failure count trigger'),
    ('memory_confidence_inject', 0.7, 0.7, 0.3, 0.95, 'inject-session-context: min confidence for memory injection'),
    ('memory_decay_rate', 0.95, 0.95, 0.8, 0.99, 'inject-session-context: per-period memory decay multiplier'),
    ('memory_decay_window_days', 30, 30, 7, 90, 'inject-session-context: days before decay kicks in'),
    ('memory_prune_threshold', 0.1, 0.1, 0.05, 0.3, 'inject-session-context: confidence below which unreinforced memories pruned'),
    ('ts_any_limit', 3, 3, 1, 8, 'verify-no-stubs: max :any uses before warning'),
    ('ts_as_any_limit', 2, 2, 1, 5, 'verify-no-stubs: max as any uses before warning'),
    ('ts_ignore_limit', 1, 1, 0, 3, 'verify-no-stubs: max @ts-ignore uses before warning'),
    ('uncommitted_file_limit', 5, 5, 2, 15, 'enforce-git-commits: modified file count before blocking'),
    ('large_change_threshold', 15, 15, 5, 50, 'session-stop-gate: files in commit before scope warning'),
    ('ai_audit_diff_threshold', 30, 30, 10, 100, 'session-stop-gate: diff lines before AI audit triggers'),
    ('outcome_retention_days', 90, 90, 30, 365, 'aggregate-session: days to keep tool_outcomes'),
    ('read_warn_lines', 1000, 1000, 500, 3000, 'enforce-read-efficiency: warn when reading files above this line count'),
    ('read_block_lines', 5000, 5000, 2000, 10000, 'enforce-read-efficiency: block full reads above this line count');" 2>/dev/null || true

  # Migration: raise read-efficiency thresholds from overly aggressive 500/2000 to 1000/5000
  sqlite3 "$METRICS_DB" "UPDATE threshold_overrides SET current_value = 1000, default_value = 1000, min_bound = 500, max_bound = 3000 WHERE metric_name = 'read_warn_lines' AND current_value <= 500;" 2>/dev/null || true
  sqlite3 "$METRICS_DB" "UPDATE threshold_overrides SET current_value = 5000, default_value = 5000, min_bound = 2000, max_bound = 10000 WHERE metric_name = 'read_block_lines' AND current_value <= 2000;" 2>/dev/null || true

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

  # Enable WAL mode and busy timeout for concurrent write safety
  sqlite3 "$METRICS_DB" "PRAGMA journal_mode=WAL;" >/dev/null 2>/dev/null || true
  sqlite3 "$METRICS_DB" "PRAGMA busy_timeout=5000;" >/dev/null 2>/dev/null || true
}

ensure_memory_db() {
  local db_dir
  db_dir=$(dirname "$MEMORY_DB")
  [ -d "$db_dir" ] || mkdir -p "$db_dir" 2>/dev/null || true

  if [ ! -f "$MEMORY_DB" ]; then
    sqlite3 "$MEMORY_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  type TEXT NOT NULL,
  name TEXT,
  description TEXT,
  tags TEXT DEFAULT '[]',
  confidence REAL DEFAULT 1.0,
  access_count INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  last_accessed TEXT,
  source TEXT DEFAULT 'human',
  file_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type);
CREATE INDEX IF NOT EXISTS idx_memories_confidence_desc ON memories(confidence DESC);

CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
  name, description, content,
  content='memories',
  content_rowid='rowid',
  tokenize='porter unicode61'
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, name, description, content)
  VALUES (new.rowid, new.name, new.description, new.content);
END;
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, name, description, content)
  VALUES ('delete', old.rowid, old.name, old.description, old.content);
  INSERT INTO memories_fts(rowid, name, description, content)
  VALUES (new.rowid, new.name, new.description, new.content);
END;
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, name, description, content)
  VALUES ('delete', old.rowid, old.name, old.description, old.content);
END;

CREATE TABLE IF NOT EXISTS project_memories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,
  content TEXT NOT NULL,
  confidence REAL DEFAULT 0.5,
  times_reinforced INTEGER DEFAULT 1,
  times_contradicted INTEGER DEFAULT 0,
  first_seen TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen TEXT NOT NULL DEFAULT (datetime('now')),
  project_type TEXT,
  source TEXT
);
CREATE INDEX IF NOT EXISTS idx_memories_category ON project_memories(category);
CREATE INDEX IF NOT EXISTS idx_memories_confidence ON project_memories(confidence DESC);

CREATE TABLE IF NOT EXISTS memory_effectiveness (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  memory_id INTEGER REFERENCES project_memories(id),
  session_id TEXT,
  was_relevant INTEGER DEFAULT 0,
  timestamp TEXT DEFAULT (datetime('now'))
);
SQL
  fi

  # Migration: add tables that may not exist yet in older memory.db files
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS memories (
    id TEXT PRIMARY KEY, content TEXT NOT NULL, type TEXT NOT NULL,
    name TEXT, description TEXT, tags TEXT DEFAULT '[]', confidence REAL DEFAULT 1.0,
    access_count INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')),
    last_accessed TEXT, source TEXT DEFAULT 'human', file_path TEXT);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_confidence_desc ON memories(confidence DESC);" 2>/dev/null || true
  # FTS5 virtual table — CREATE VIRTUAL TABLE doesn't support IF NOT EXISTS in all SQLite builds
  sqlite3 "$MEMORY_DB" "CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    name, description, content, content='memories', content_rowid='rowid',
    tokenize='porter unicode61');" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, name, description, content)
    VALUES (new.rowid, new.name, new.description, new.content); END;" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, name, description, content)
    VALUES ('delete', old.rowid, old.name, old.description, old.content);
    INSERT INTO memories_fts(rowid, name, description, content)
    VALUES (new.rowid, new.name, new.description, new.content); END;" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, name, description, content)
    VALUES ('delete', old.rowid, old.name, old.description, old.content); END;" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS project_memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, content TEXT NOT NULL,
    confidence REAL DEFAULT 0.5, times_reinforced INTEGER DEFAULT 1, times_contradicted INTEGER DEFAULT 0,
    first_seen TEXT NOT NULL DEFAULT (datetime('now')), last_seen TEXT NOT NULL DEFAULT (datetime('now')),
    project_type TEXT, source TEXT);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_category ON project_memories(category);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE INDEX IF NOT EXISTS idx_memories_confidence ON project_memories(confidence DESC);" 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "CREATE TABLE IF NOT EXISTS memory_effectiveness (
    id INTEGER PRIMARY KEY AUTOINCREMENT, memory_id INTEGER REFERENCES project_memories(id),
    session_id TEXT, was_relevant INTEGER DEFAULT 0, timestamp TEXT DEFAULT (datetime('now')));" 2>/dev/null || true

  # Enable WAL mode and busy timeout for concurrent write safety
  sqlite3 "$MEMORY_DB" "PRAGMA journal_mode=WAL;" >/dev/null 2>/dev/null || true
  sqlite3 "$MEMORY_DB" "PRAGMA busy_timeout=5000;" >/dev/null 2>/dev/null || true
}
