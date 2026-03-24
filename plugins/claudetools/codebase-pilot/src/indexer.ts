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

/** Skip indexing if a project has more source files than this */
const MAX_SOURCE_FILES = 10_000;

const FILE_PATTERNS = [
  "**/*.ts",
  "**/*.tsx",
  "**/*.js",
  "**/*.jsx",
  "**/*.mjs",
  "**/*.cjs",
  "**/*.py",
  "**/*.go",
  "**/*.rs",
  "**/*.java",
  "**/*.kt",
  "**/*.kts",
  "**/*.rb",
  "**/*.cs",
  "**/*.php",
  "**/*.swift",
  "**/*.c",
  "**/*.h",
  "**/*.cpp",
  "**/*.hpp",
  "**/*.cc",
  "**/*.cxx",
  "**/*.sh",
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

export interface SingleFileStats {
  symbols: number;
  imports: number;
  durationMs: number;
  deleted: boolean;
}

export async function indexSingleFile(projectRoot: string, relPath: string): Promise<SingleFileStats> {
  const startTime = Date.now();
  const db = openDatabase(projectRoot);
  // Wait up to 3s for concurrent writes (e.g. rapid sequential edits)
  db.pragma("busy_timeout = 3000");
  const stmts = prepareStatements(db);

  const absPath = path.join(projectRoot, relPath);
  const fileExists = fs.existsSync(absPath);

  let totalSymbols = 0;
  let totalImports = 0;
  let deleted = false;

  // Parse outside the transaction (parseFile is async for WASM languages)
  let parseResult: { language: string; result: import("./parser.js").ParseResult; stat: fs.Stats } | null = null;

  if (fileExists) {
    const language = detectLanguage(relPath);
    if (language) {
      const stat = fs.statSync(absPath);
      const source = fs.readFileSync(absPath, "utf-8");
      try {
        const result = await parseFile(source, language);
        parseResult = { language, result, stat };
      } catch {
        // Skip files that fail to parse
      }
    }
  }

  const reindex = db.transaction(() => {
    const existing = stmts.getFile.get(relPath) as
      | { id: number; modified_at: number; size: number }
      | undefined;

    if (!fileExists) {
      // File was deleted — remove from index
      if (existing) {
        stmts.deleteSymbolsByFile.run(existing.id);
        stmts.deleteImportsByFile.run(existing.id);
        stmts.deleteFile.run(relPath);
        deleted = true;
      }
      return;
    }

    if (!parseResult) return;

    const { language, result, stat } = parseResult;
    const mtimeMs = Math.floor(stat.mtimeMs);
    const size = stat.size;

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

    // Insert symbols (with parent tracking)
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
  });

  reindex();
  db.close();

  return {
    symbols: totalSymbols,
    imports: totalImports,
    durationMs: Date.now() - startTime,
    deleted,
  };
}

export async function indexProject(projectRoot: string): Promise<IndexStats> {
  const startTime = Date.now();

  // Validate project root exists
  if (!fs.existsSync(projectRoot)) {
    throw new Error(`Project root does not exist: ${projectRoot}`);
  }

  // Find all source files (wrapped to catch glob permission/fs errors)
  let files: string[];
  try {
    files = glob.sync(FILE_PATTERNS, {
      cwd: projectRoot,
      ignore: IGNORED_DIRS.flatMap((d) => [`${d}/**`, `**/${d}/**`]),
      nodir: true,
      absolute: false,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`File discovery failed: ${msg}`);
  }

  // Guard against enormous repos that would overwhelm memory/time
  if (files.length > MAX_SOURCE_FILES) {
    throw new Error(
      `Project has ${files.length} source files (limit: ${MAX_SOURCE_FILES}). ` +
      `Indexing skipped to avoid resource exhaustion.`
    );
  }

  let db: ReturnType<typeof openDatabase>;
  try {
    db = openDatabase(projectRoot);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Database open failed: ${msg}`);
  }
  const stmts = prepareStatements(db);

  let indexedFiles = 0;
  let skippedFiles = 0;
  let removedFiles = 0;
  let totalSymbols = 0;
  let totalImports = 0;

  // Track which files we've seen (for detecting deletions)
  const seenPaths = new Set<string>();

  // Pre-parse all files that need updating (async parsing happens outside the transaction)
  interface ParsedFile {
    relPath: string;
    language: string;
    result: import("./parser.js").ParseResult;
    mtimeMs: number;
    size: number;
  }

  const parsedFiles: ParsedFile[] = [];
  const unchangedFiles: { relPath: string; existingId: number }[] = [];

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
      unchangedFiles.push({ relPath, existingId: existing.id });
      continue;
    }

    const language = detectLanguage(relPath);
    if (!language) {
      skippedFiles++;
      continue;
    }

    // Read and parse the file (await for WASM languages)
    const source = fs.readFileSync(absPath, "utf-8");
    try {
      const result = await parseFile(source, language);
      parsedFiles.push({ relPath, language, result, mtimeMs, size });
    } catch {
      skippedFiles++;
    }
  }

  // Now run the synchronous transaction with pre-parsed results
  const indexAll = db.transaction(() => {
    // Count unchanged files
    for (const { existingId } of unchangedFiles) {
      skippedFiles++;
      const count = db
        .prepare("SELECT COUNT(*) as n FROM symbols WHERE file_id = ?")
        .get(existingId) as { n: number };
      totalSymbols += count.n;
      const impCount = db
        .prepare("SELECT COUNT(*) as n FROM imports WHERE file_id = ?")
        .get(existingId) as { n: number };
      totalImports += impCount.n;
    }

    // Insert/update parsed files
    for (const { relPath, language, result, mtimeMs, size } of parsedFiles) {
      const existing = stmts.getFile.get(relPath) as
        | { id: number; modified_at: number; size: number }
        | undefined;

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

  try {
    indexAll();
  } catch (err) {
    try { db.close(); } catch { /* ignore close error */ }
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Index transaction failed: ${msg}`);
  }
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
