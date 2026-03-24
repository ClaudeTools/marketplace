import Database from "better-sqlite3";
import path from "node:path";
import fs from "node:fs";
import { initializeSchema, checkSchemaVersion } from "./schema.js";

const DB_DIR = ".codeindex";
const DB_FILE = "db.sqlite";

export function getDbPath(projectRoot: string): string {
  return path.join(projectRoot, DB_DIR, DB_FILE);
}

export function openDatabase(projectRoot: string): Database.Database {
  const dbDir = path.join(projectRoot, DB_DIR);
  try {
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true });
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot create index directory ${dbDir}: ${msg}`);
  }

  const dbPath = getDbPath(projectRoot);
  let db: Database.Database;
  try {
    db = new Database(dbPath);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot open database ${dbPath}: ${msg}`);
  }

  // Enable WAL mode and busy timeout for concurrent write safety
  try {
    db.pragma('journal_mode = WAL');
    db.pragma('busy_timeout = 5000');
  } catch {
    // WAL mode may fail on some filesystems (e.g., network mounts) — continue with default journal
  }

  // Check schema version — if mismatch, recreate
  try {
    if (!checkSchemaVersion(db)) {
      // Drop all tables and recreate
      db.exec(`
        DROP TABLE IF EXISTS imports;
        DROP TABLE IF EXISTS symbols;
        DROP TABLE IF EXISTS files;
        DROP TABLE IF EXISTS meta;
      `);
      // FTS table needs special handling
      try {
        db.exec("DROP TABLE IF EXISTS symbols_fts");
      } catch {
        // FTS table might not exist
      }
      // Drop triggers
      db.exec(`
        DROP TRIGGER IF EXISTS symbols_ai;
        DROP TRIGGER IF EXISTS symbols_ad;
        DROP TRIGGER IF EXISTS symbols_au;
      `);
    }
  } catch (err) {
    // Schema check failed (corrupt DB) — delete and recreate from scratch
    try { db.close(); } catch { /* ignore */ }
    try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
    try {
      db = new Database(dbPath);
      db.pragma('journal_mode = WAL');
      db.pragma('busy_timeout = 5000');
    } catch (innerErr) {
      const msg = innerErr instanceof Error ? innerErr.message : String(innerErr);
      throw new Error(`Cannot recreate database after corruption: ${msg}`);
    }
  }

  initializeSchema(db);
  return db;
}

// Prepared statement cache for the indexer
export interface DbStatements {
  insertFile: Database.Statement;
  updateFile: Database.Statement;
  getFile: Database.Statement;
  deleteFile: Database.Statement;
  deleteSymbolsByFile: Database.Statement;
  deleteImportsByFile: Database.Statement;
  insertSymbol: Database.Statement;
  insertImport: Database.Statement;
  getAllFiles: Database.Statement;
}

export function prepareStatements(db: Database.Database): DbStatements {
  return {
    insertFile: db.prepare(`
      INSERT INTO files (path, language, size, modified_at, hash)
      VALUES (@path, @language, @size, @modified_at, @hash)
    `),
    updateFile: db.prepare(`
      UPDATE files SET language = @language, size = @size, modified_at = @modified_at, hash = @hash
      WHERE path = @path
    `),
    getFile: db.prepare("SELECT * FROM files WHERE path = ?"),
    deleteFile: db.prepare("DELETE FROM files WHERE path = ?"),
    deleteSymbolsByFile: db.prepare("DELETE FROM symbols WHERE file_id = ?"),
    deleteImportsByFile: db.prepare("DELETE FROM imports WHERE file_id = ?"),
    insertSymbol: db.prepare(`
      INSERT INTO symbols (file_id, name, kind, line, end_line, signature, exported, parent_id)
      VALUES (@file_id, @name, @kind, @line, @end_line, @signature, @exported, @parent_id)
    `),
    insertImport: db.prepare(`
      INSERT INTO imports (file_id, source, symbols)
      VALUES (@file_id, @source, @symbols)
    `),
    getAllFiles: db.prepare("SELECT * FROM files"),
  };
}
