import Database from "better-sqlite3";
import path from "node:path";
import fs from "node:fs";
import { initializeSchema, checkSchemaVersion } from "./schema.js";
const DB_DIR = ".codeindex";
const DB_FILE = "db.sqlite";
export function getDbPath(projectRoot) {
    return path.join(projectRoot, DB_DIR, DB_FILE);
}
export function openDatabase(projectRoot) {
    const dbDir = path.join(projectRoot, DB_DIR);
    if (!fs.existsSync(dbDir)) {
        fs.mkdirSync(dbDir, { recursive: true });
    }
    const dbPath = getDbPath(projectRoot);
    const db = new Database(dbPath);
    // Check schema version — if mismatch, recreate
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
        }
        catch {
            // FTS table might not exist
        }
        // Drop triggers
        db.exec(`
      DROP TRIGGER IF EXISTS symbols_ai;
      DROP TRIGGER IF EXISTS symbols_ad;
      DROP TRIGGER IF EXISTS symbols_au;
    `);
    }
    initializeSchema(db);
    return db;
}
export function prepareStatements(db) {
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
//# sourceMappingURL=db.js.map