-- Cross-project plugin feedback: structured reviews from agents in any repo
-- Each report = one agent review session; items = normalized findings for aggregation

CREATE TABLE feedback_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  install_id TEXT NOT NULL,
  plugin_version TEXT,
  project_type TEXT,
  project_size TEXT,
  overall_grade TEXT,
  model_family TEXT,
  os TEXT,
  review_type TEXT DEFAULT 'manual',
  report_json TEXT NOT NULL DEFAULT '{}',
  received_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE feedback_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  report_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  component TEXT NOT NULL,
  severity TEXT,
  title TEXT NOT NULL,
  description TEXT,
  FOREIGN KEY (report_id) REFERENCES feedback_reports(id)
);

CREATE INDEX idx_fb_reports_install ON feedback_reports(install_id);
CREATE INDEX idx_fb_reports_ts ON feedback_reports(ts);
CREATE INDEX idx_fb_reports_grade ON feedback_reports(overall_grade);
CREATE INDEX idx_fb_reports_project ON feedback_reports(project_type);
CREATE INDEX idx_fb_items_category ON feedback_items(category);
CREATE INDEX idx_fb_items_component ON feedback_items(component);
CREATE INDEX idx_fb_items_report ON feedback_items(report_id);
