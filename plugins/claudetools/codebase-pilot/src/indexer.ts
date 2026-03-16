import fs from "node:fs";
import path from "node:path";
import { glob } from "glob";
import type Database from "better-sqlite3";
import { openDatabase, prepareStatements, type DbStatements } from "./db.js";
import {
  parseFile,
  detectLanguage,
  type ExtractedSymbol,
  type ExtractedImport,
} from "./parser.js";

const IGNORED_DIRS = [
  "node_modules",
  ".git",
  "dist",
  "build",
  ".next",
  ".codeindex",
  "coverage",
  ".turbo",
  ".cache",
  "__pycache__",
  ".venv",
  "vendor",
  "target",
];

const FILE_PATTERNS = [
  "**/*.ts",
  "**/*.tsx",
  "**/*.js",
  "**/*.jsx",
  "**/*.mjs",
  "**/*.cjs",
];

export interface IndexStats {
  totalFiles: number;
  indexedFiles: number;
  skippedFiles: number;
  removedFiles: number;
  totalSymbols: number;
  totalImports: number;
  durationMs: number;
}

export function indexProject(projectRoot: string): IndexStats {
  const startTime = Date.now();
  const db = openDatabase(projectRoot);
  const stmts = prepareStatements(db);

  let indexedFiles = 0;
  let skippedFiles = 0;
  let removedFiles = 0;
  let totalSymbols = 0;
  let totalImports = 0;

  // Find all source files
  const files = glob.sync(FILE_PATTERNS, {
    cwd: projectRoot,
    ignore: IGNORED_DIRS.flatMap((d) => [`${d}/**`, `**/${d}/**`]),
    nodir: true,
    absolute: false,
  });

  // Track which files we've seen (for detecting deletions)
  const seenPaths = new Set<string>();

  // Index each file (in a transaction for performance)
  const indexAll = db.transaction(() => {
    for (const relPath of files) {
      seenPaths.add(relPath);
      const absPath = path.join(projectRoot, relPath);

      let stat;
      try {
        stat = fs.statSync(absPath);
      } catch {
        continue;
      }
      if (!stat.isFile()) continue;

      const mtimeMs = Math.floor(stat.mtimeMs);
      const size = stat.size;

      // Check if file is already indexed and unchanged
      const existing = stmts.getFile.get(relPath) as
        | { id: number; modified_at: number; size: number }
        | undefined;

      if (existing && existing.modified_at === mtimeMs && existing.size === size) {
        skippedFiles++;
        // Count existing symbols for stats
        const count = db
          .prepare("SELECT COUNT(*) as n FROM symbols WHERE file_id = ?")
          .get(existing.id) as { n: number };
        totalSymbols += count.n;
        const impCount = db
          .prepare("SELECT COUNT(*) as n FROM imports WHERE file_id = ?")
          .get(existing.id) as { n: number };
        totalImports += impCount.n;
        continue;
      }

      const language = detectLanguage(relPath);
      if (!language) {
        skippedFiles++;
        continue;
      }

      // Read and parse the file
      const source = fs.readFileSync(absPath, "utf-8");
      let result;
      try {
        result = parseFile(source, language);
      } catch (err) {
        // Skip files that fail to parse
        skippedFiles++;
        continue;
      }

      // Upsert file record
      if (existing) {
        stmts.deleteSymbolsByFile.run(existing.id);
        stmts.deleteImportsByFile.run(existing.id);
        stmts.updateFile.run({
          path: relPath,
          language,
          size,
          modified_at: mtimeMs,
          hash: null,
        });
      } else {
        stmts.insertFile.run({
          path: relPath,
          language,
          size,
          modified_at: mtimeMs,
          hash: null,
        });
      }

      const fileRow = stmts.getFile.get(relPath) as { id: number };
      const fileId = fileRow.id;

      // Insert symbols (with parent tracking for class/interface members)
      const insertSymbolTree = (
        symbols: ExtractedSymbol[],
        parentId: number | null
      ) => {
        for (const sym of symbols) {
          const info = stmts.insertSymbol.run({
            file_id: fileId,
            name: sym.name,
            kind: sym.kind,
            line: sym.line,
            end_line: sym.endLine,
            signature: sym.signature,
            exported: sym.exported ? 1 : 0,
            parent_id: parentId,
          });
          totalSymbols++;

          if (sym.children.length > 0) {
            insertSymbolTree(sym.children, Number(info.lastInsertRowid));
          }
        }
      };

      insertSymbolTree(result.symbols, null);

      // Insert imports
      for (const imp of result.imports) {
        stmts.insertImport.run({
          file_id: fileId,
          source: imp.source,
          symbols: imp.symbols.length > 0 ? imp.symbols.join(", ") : null,
        });
        totalImports++;
      }

      indexedFiles++;
    }

    // Remove files that no longer exist
    const allDbFiles = stmts.getAllFiles.all() as { id: number; path: string }[];
    for (const dbFile of allDbFiles) {
      if (!seenPaths.has(dbFile.path)) {
        stmts.deleteSymbolsByFile.run(dbFile.id);
        stmts.deleteImportsByFile.run(dbFile.id);
        stmts.deleteFile.run(dbFile.path);
        removedFiles++;
      }
    }
  });

  indexAll();
  db.close();

  return {
    totalFiles: files.length,
    indexedFiles,
    skippedFiles,
    removedFiles,
    totalSymbols,
    totalImports,
    durationMs: Date.now() - startTime,
  };
}
