#!/usr/bin/env node

import { indexProject } from "./indexer.js";
import { generateProjectMap } from "./project-map.js";
import { startMcpServer } from "./mcp-server.js";
import Database from "better-sqlite3";
import { getDbPath } from "./db.js";

const USAGE_TEXT = `Usage: codebase-pilot <command> [options]

Commands:
  index [path]           Index a project (default: current directory)
  map [path]             Generate project map
  find-symbol <name>     Search for a symbol
  mcp-server             Start MCP server (stdio)

Options:
  --kind <kind>          Filter find-symbol by kind
  --project <path>       Project root (default: cwd)`;

const cliArgs = process.argv.slice(2);
const command = cliArgs[0];

function getProjectRoot(): string {
  const pathIdx = cliArgs.indexOf("--project");
  if (pathIdx !== -1 && cliArgs[pathIdx + 1]) {
    return cliArgs[pathIdx + 1];
  }
  const cmdArgs = cliArgs.slice(1).filter((a: string) => !a.startsWith("--"));
  return cmdArgs[0] ?? process.cwd();
}

function runIndex(): void {
  const projectRoot = getProjectRoot();
  const stats = indexProject(projectRoot);
  const summary = [
    `Indexed ${stats.indexedFiles} files (${stats.skippedFiles} unchanged, ${stats.removedFiles} removed)`,
    `${stats.totalSymbols} symbols, ${stats.totalImports} imports in ${stats.durationMs}ms`,
  ].join("\n");
  process.stderr.write(summary + "\n");
}

function runMap(): void {
  const projectRoot = getProjectRoot();
  const map = generateProjectMap(projectRoot);
  process.stdout.write(map);
}

function runFindSymbol(): void {
  const name = cliArgs[1];
  if (!name || name.startsWith("--")) {
    process.stderr.write("Error: symbol name required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }

  const kindIdx = cliArgs.indexOf("--kind");
  const kind = kindIdx !== -1 ? cliArgs[kindIdx + 1] : undefined;

  const projectRoot = getProjectRoot();
  const dbPath = getDbPath(projectRoot);
  const db = new Database(dbPath, { readonly: true });

  const sanitized = name.replace(/[^\w*]/g, "");
  if (!sanitized) {
    db.close();
    process.stderr.write("Invalid search term\n");
    process.exit(1);
  }

  const ftsQuery = sanitized.endsWith("*") ? sanitized : `${sanitized}*`;

  interface ResultRow {
    name: string;
    kind: string;
    line: number;
    signature: string | null;
    exported: number;
    path: string;
  }

  const query = kind
    ? db.prepare(
        `SELECT s.name, s.kind, s.line, s.signature, s.exported, f.path
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         WHERE symbols_fts MATCH ? AND s.kind = ?
         ORDER BY rank LIMIT 30`
      )
    : db.prepare(
        `SELECT s.name, s.kind, s.line, s.signature, s.exported, f.path
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         WHERE symbols_fts MATCH ?
         ORDER BY rank LIMIT 30`
      );

  const results = (kind ? query.all(ftsQuery, kind) : query.all(ftsQuery)) as ResultRow[];
  db.close();

  if (results.length === 0) {
    process.stdout.write(`No symbols found matching "${name}"\n`);
    return;
  }

  const output = results
    .map((r) => {
      const exported = r.exported ? " [exported]" : "";
      const sig = r.signature ? ` — ${r.signature}` : "";
      return `${r.kind} ${r.name}${exported} ${r.path}:${r.line}${sig}`;
    })
    .join("\n");
  process.stdout.write(output + "\n");
}

function runMcpServer(): void {
  if (!process.env.CODEBASE_PILOT_PROJECT_ROOT) {
    process.env.CODEBASE_PILOT_PROJECT_ROOT = getProjectRoot();
  }
  startMcpServer().catch((err: unknown) => {
    process.stderr.write("MCP server error: " + String(err) + "\n");
    process.exit(1);
  });
}

switch (command) {
  case "index":
    runIndex();
    break;
  case "map":
    runMap();
    break;
  case "find-symbol":
    runFindSymbol();
    break;
  case "mcp-server":
    runMcpServer();
    break;
  default:
    if (command) {
      process.stderr.write(`Unknown command: ${command}\n`);
    }
    process.stderr.write(USAGE_TEXT + "\n");
    process.exit(1);
}
