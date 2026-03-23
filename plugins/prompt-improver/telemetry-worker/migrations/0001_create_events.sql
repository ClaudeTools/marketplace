CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  install_id TEXT NOT NULL,
  plugin_version TEXT,
  component TEXT NOT NULL,
  event TEXT NOT NULL,
  decision TEXT,
  duration_ms INTEGER DEFAULT 0,
  model_family TEXT,
  os TEXT,
  extra TEXT DEFAULT '{}',
  received_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_events_install ON events(install_id);
CREATE INDEX idx_events_component ON events(component);
CREATE INDEX idx_events_ts ON events(ts);
CREATE INDEX idx_events_decision ON events(decision);
