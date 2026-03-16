export const SCHEMA_VERSION = 1;
export function initializeSchema(db) {
    db.pragma("journal_mode = WAL");
    db.pragma("synchronous = NORMAL");
    db.pragma("cache_size = -16000"); // 16MB
    db.pragma("temp_store = MEMORY");
    db.exec(`
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY,
      path TEXT UNIQUE NOT NULL,
      language TEXT,
      size INTEGER,
      modified_at INTEGER,
      hash TEXT
    );

    CREATE TABLE IF NOT EXISTS symbols (
      id INTEGER PRIMARY KEY,
      file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      line INTEGER NOT NULL,
      end_line INTEGER,
      signature TEXT,
      exported INTEGER DEFAULT 0,
      parent_id INTEGER REFERENCES symbols(id)
    );

    CREATE TABLE IF NOT EXISTS imports (
      id INTEGER PRIMARY KEY,
      file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
      source TEXT NOT NULL,
      symbols TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file_id);
    CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
    CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind);
    CREATE INDEX IF NOT EXISTS idx_imports_file ON imports(file_id);
    CREATE INDEX IF NOT EXISTS idx_imports_source ON imports(source);
    CREATE INDEX IF NOT EXISTS idx_files_path ON files(path);
  `);
    // FTS5 virtual table for symbol search
    // Check if it exists first (CREATE VIRTUAL TABLE IF NOT EXISTS not always reliable)
    const ftsExists = db
        .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='symbols_fts'")
        .get();
    if (!ftsExists) {
        db.exec(`
      CREATE VIRTUAL TABLE symbols_fts USING fts5(
        name,
        signature,
        content=symbols,
        content_rowid=id
      );
    `);
    }
    // Triggers to keep FTS in sync with symbols table
    db.exec(`
    CREATE TRIGGER IF NOT EXISTS symbols_ai AFTER INSERT ON symbols BEGIN
      INSERT INTO symbols_fts(rowid, name, signature)
      VALUES (new.id, new.name, COALESCE(new.signature, ''));
    END;

    CREATE TRIGGER IF NOT EXISTS symbols_ad AFTER DELETE ON symbols BEGIN
      INSERT INTO symbols_fts(symbols_fts, rowid, name, signature)
      VALUES('delete', old.id, old.name, COALESCE(old.signature, ''));
    END;

    CREATE TRIGGER IF NOT EXISTS symbols_au AFTER UPDATE ON symbols BEGIN
      INSERT INTO symbols_fts(symbols_fts, rowid, name, signature)
      VALUES('delete', old.id, old.name, COALESCE(old.signature, ''));
      INSERT INTO symbols_fts(rowid, name, signature)
      VALUES (new.id, new.name, COALESCE(new.signature, ''));
    END;
  `);
    // Store schema version
    db.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?)").run(String(SCHEMA_VERSION));
}
export function checkSchemaVersion(db) {
    try {
        const row = db
            .prepare("SELECT value FROM meta WHERE key = 'schema_version'")
            .get();
        return row?.value === String(SCHEMA_VERSION);
    }
    catch {
        return false;
    }
}
//# sourceMappingURL=schema.js.map