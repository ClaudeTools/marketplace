-- Enrich feedback schema with narrative fields and cross-references
-- Addresses signal loss: narrative reasoning, self-critique, component grades, item relationships

ALTER TABLE feedback_reports ADD COLUMN narrative TEXT;
ALTER TABLE feedback_reports ADD COLUMN self_critique TEXT;

CREATE TABLE IF NOT EXISTS feedback_component_grades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  report_id INTEGER NOT NULL,
  component TEXT NOT NULL,
  grade TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (report_id) REFERENCES feedback_reports(id)
);

ALTER TABLE feedback_items ADD COLUMN related_items TEXT DEFAULT '[]';

CREATE INDEX idx_fb_grades_report ON feedback_component_grades(report_id);
CREATE INDEX idx_fb_grades_component ON feedback_component_grades(component);
