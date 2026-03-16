import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import Database from "better-sqlite3";
import path from "node:path";
import { getDbPath } from "./db.js";
import { generateProjectMap } from "./project-map.js";

export interface SymbolRow {
  name: string;
  kind: string;
  line: number;
  end_line: number | null;
  signature: string | null;
  exported: number;
  path: string;
  parent_name: string | null;
}

export interface ImportRow {
  path: string;
  symbols: string | null;
}

export interface FileSymbolRow {
  name: string;
  kind: string;
  line: number;
  end_line: number | null;
  signature: string | null;
  exported: number;
  parent_name: string | null;
}

export interface RelatedRow {
  path: string;
  source: string;
  symbols: string | null;
  direction: string;
}

export function escapeLike(input: string): string {
  return input.replace(/[%_\\]/g, "\\$&");
}

function getProjectRoot(): string {
  return process.env.CODEBASE_PILOT_PROJECT_ROOT ?? process.cwd();
}

function openReadonly(): Database.Database {
  const projectRoot = getProjectRoot();
  const dbPath = getDbPath(projectRoot);
  return new Database(dbPath, { readonly: true });
}

const TOOLS = [
  {
    name: "project_map",
    description:
      "Returns a structured overview of the project: name, languages, directory structure, entry points, and key exports. Use this to orient yourself in an unfamiliar codebase.",
    inputSchema: {
      type: "object" as const,
      properties: {},
    },
  },
  {
    name: "find_symbol",
    description:
      "Search for symbols (functions, classes, types, interfaces, variables) by name. Returns file path, line number, kind, and signature for each match. Supports prefix matching.",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: {
          type: "string",
          description: "Symbol name to search for (supports prefix matching)",
        },
        kind: {
          type: "string",
          description:
            "Optional filter by kind: function, class, interface, type, enum, variable, method, property",
          enum: [
            "function",
            "class",
            "interface",
            "type",
            "enum",
            "variable",
            "method",
            "property",
          ],
        },
      },
      required: ["name"],
    },
  },
  {
    name: "find_usages",
    description:
      "Find all files that import a given symbol name. Shows which files depend on a symbol and what they import from its source.",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: {
          type: "string",
          description: "Symbol name to find usages of",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "file_overview",
    description:
      "List all symbols defined in a specific file, grouped by kind. Shows structure without source code — useful for understanding a file before reading it.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Relative file path from project root",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "related_files",
    description:
      "Find files connected to a given file via import relationships — both files it imports from and files that import from it.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Relative file path from project root",
        },
      },
      required: ["path"],
    },
  },
];

export function handleProjectMap(): string {
  const projectRoot = getProjectRoot();
  return generateProjectMap(projectRoot);
}

export function handleFindSymbol(args: { name: string; kind?: string }): string {
  const db = openReadonly();

  // Sanitize the search term for FTS5
  const sanitized = args.name.replace(/[^\w*]/g, "");
  if (!sanitized) {
    db.close();
    return "Invalid search term";
  }

  // Use FTS5 for search — add wildcard for prefix matching
  const ftsQuery = sanitized.endsWith("*") ? sanitized : `${sanitized}*`;

  let results: SymbolRow[];
  if (args.kind) {
    results = db
      .prepare(
        `SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
                f.path, ps.name as parent_name
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         LEFT JOIN symbols ps ON s.parent_id = ps.id
         WHERE symbols_fts MATCH ? AND s.kind = ?
         ORDER BY rank
         LIMIT 30`
      )
      .all(ftsQuery, args.kind) as SymbolRow[];
  } else {
    results = db
      .prepare(
        `SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
                f.path, ps.name as parent_name
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         LEFT JOIN symbols ps ON s.parent_id = ps.id
         WHERE symbols_fts MATCH ?
         ORDER BY rank
         LIMIT 30`
      )
      .all(ftsQuery) as SymbolRow[];
  }

  db.close();

  if (results.length === 0) {
    return `No symbols found matching "${args.name}"`;
  }

  const lines: string[] = [`Found ${results.length} match(es) for "${args.name}":`];
  for (const r of results) {
    const exported = r.exported ? " [exported]" : "";
    const parent = r.parent_name ? ` in ${r.parent_name}` : "";
    const sig = r.signature ? ` — ${r.signature}` : "";
    lines.push(`  ${r.kind} ${r.name}${parent}${exported}`);
    lines.push(`    ${r.path}:${r.line}${sig}`);
  }

  return lines.join("\n");
}

export function handleFindUsages(args: { name: string }): string {
  const db = openReadonly();

  // Find files that import this symbol
  const safeName = escapeLike(args.name);
  const results = db
    .prepare(
      `SELECT f.path, i.symbols
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.symbols LIKE ? ESCAPE '\\'
       ORDER BY f.path
       LIMIT 50`
    )
    .all(`%${safeName}%`) as ImportRow[];

  db.close();

  if (results.length === 0) {
    return `No files import "${args.name}"`;
  }

  const lines: string[] = [`${results.length} file(s) import "${args.name}":`];
  for (const r of results) {
    lines.push(`  ${r.path} — imports: ${r.symbols ?? "(default)"}`);
  }

  return lines.join("\n");
}

export function handleFileOverview(args: { path: string }): string {
  const db = openReadonly();

  const file = db
    .prepare("SELECT id, language, size FROM files WHERE path = ?")
    .get(args.path) as { id: number; language: string; size: number } | undefined;

  if (!file) {
    db.close();
    return `File not found in index: ${args.path}`;
  }

  const symbols = db
    .prepare(
      `SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
              ps.name as parent_name
       FROM symbols s
       LEFT JOIN symbols ps ON s.parent_id = ps.id
       WHERE s.file_id = ?
       ORDER BY s.line`
    )
    .all(file.id) as FileSymbolRow[];

  const imports = db
    .prepare("SELECT source, symbols FROM imports WHERE file_id = ? ORDER BY source")
    .all(file.id) as { source: string; symbols: string | null }[];

  db.close();

  const lines: string[] = [
    `## ${args.path}`,
    `Language: ${file.language} | Size: ${file.size} bytes | ${symbols.length} symbols`,
    "",
  ];

  if (imports.length > 0) {
    lines.push("### Imports");
    for (const imp of imports) {
      const syms = imp.symbols ? ` { ${imp.symbols} }` : "";
      lines.push(`  from "${imp.source}"${syms}`);
    }
    lines.push("");
  }

  if (symbols.length > 0) {
    lines.push("### Symbols");
    for (const sym of symbols) {
      const exported = sym.exported ? " [exported]" : "";
      const parent = sym.parent_name ? ` (in ${sym.parent_name})` : "";
      const sig = sym.signature ? ` — ${sym.signature}` : "";
      lines.push(`  L${sym.line} ${sym.kind} ${sym.name}${parent}${exported}${sig}`);
    }
  }

  return lines.join("\n");
}

export function handleRelatedFiles(args: { path: string }): string {
  const db = openReadonly();

  const file = db
    .prepare("SELECT id FROM files WHERE path = ?")
    .get(args.path) as { id: number } | undefined;

  if (!file) {
    db.close();
    return `File not found in index: ${args.path}`;
  }

  // Files this file imports from
  const importsFrom = db
    .prepare(
      `SELECT i.source, i.symbols
       FROM imports i
       WHERE i.file_id = ?
       ORDER BY i.source`
    )
    .all(file.id) as { source: string; symbols: string | null }[];

  // Files that import from this file (by matching import source to this file's path)
  const basename = args.path.replace(/\.(ts|tsx|js|jsx|mjs|cjs)$/, "");
  const safeBasename = escapeLike(path.basename(basename));
  const safeFullBasename = escapeLike(basename);
  const importedBy = db
    .prepare(
      `SELECT f.path, i.source, i.symbols, 'imported_by' as direction
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.source LIKE ? ESCAPE '\\' OR i.source LIKE ? ESCAPE '\\' OR i.source LIKE ? ESCAPE '\\'
       ORDER BY f.path
       LIMIT 30`
    )
    .all(
      `%${safeBasename}`,
      `%/${safeFullBasename}`,
      `./${safeFullBasename}`
    ) as RelatedRow[];

  db.close();

  const lines: string[] = [`## Related files for ${args.path}`, ""];

  if (importsFrom.length > 0) {
    lines.push("### Imports from");
    for (const imp of importsFrom) {
      const syms = imp.symbols ? ` { ${imp.symbols} }` : "";
      lines.push(`  ${imp.source}${syms}`);
    }
    lines.push("");
  }

  if (importedBy.length > 0) {
    lines.push("### Imported by");
    for (const dep of importedBy) {
      const syms = dep.symbols ? ` { ${dep.symbols} }` : "";
      lines.push(`  ${dep.path}${syms}`);
    }
    lines.push("");
  }

  if (importsFrom.length === 0 && importedBy.length === 0) {
    lines.push("No import relationships found for this file.");
  }

  return lines.join("\n");
}

export async function startMcpServer(): Promise<void> {
  const server = new Server(
    { name: "codebase-pilot", version: "1.0.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
      let result: string;
      switch (name) {
        case "project_map":
          result = handleProjectMap();
          break;
        case "find_symbol":
          result = handleFindSymbol(args as { name: string; kind?: string });
          break;
        case "find_usages":
          result = handleFindUsages(args as { name: string });
          break;
        case "file_overview":
          result = handleFileOverview(args as { path: string });
          break;
        case "related_files":
          result = handleRelatedFiles(args as { path: string });
          break;
        default:
          result = `Unknown tool: ${name}`;
      }

      return {
        content: [{ type: "text", text: result }],
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        content: [{ type: "text", text: `Error: ${message}` }],
        isError: true,
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
}
