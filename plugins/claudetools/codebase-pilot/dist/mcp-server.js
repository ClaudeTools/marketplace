import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import Database from "better-sqlite3";
import path from "node:path";
import { getDbPath } from "./db.js";
import { generateProjectMap } from "./project-map.js";
function getProjectRoot() {
    return process.env.CODEBASE_PILOT_PROJECT_ROOT ?? process.cwd();
}
function openReadonly() {
    const projectRoot = getProjectRoot();
    const dbPath = getDbPath(projectRoot);
    return new Database(dbPath, { readonly: true });
}
const TOOLS = [
    {
        name: "project_map",
        description: "Returns a structured overview of the project: name, languages, directory structure, entry points, and key exports. Use this to orient yourself in an unfamiliar codebase.",
        inputSchema: {
            type: "object",
            properties: {},
        },
    },
    {
        name: "find_symbol",
        description: "Search for symbols (functions, classes, types, interfaces, variables) by name. Returns file path, line number, kind, and signature for each match. Supports prefix matching.",
        inputSchema: {
            type: "object",
            properties: {
                name: {
                    type: "string",
                    description: "Symbol name to search for (supports prefix matching)",
                },
                kind: {
                    type: "string",
                    description: "Optional filter by kind: function, class, interface, type, enum, variable, method, property",
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
        description: "Find all files that import a given symbol name. Shows which files depend on a symbol and what they import from its source.",
        inputSchema: {
            type: "object",
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
        description: "List all symbols defined in a specific file, grouped by kind. Shows structure without source code — useful for understanding a file before reading it.",
        inputSchema: {
            type: "object",
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
        description: "Find files connected to a given file via import relationships — both files it imports from and files that import from it.",
        inputSchema: {
            type: "object",
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
function handleProjectMap() {
    const projectRoot = getProjectRoot();
    return generateProjectMap(projectRoot);
}
function handleFindSymbol(args) {
    const db = openReadonly();
    // Sanitize the search term for FTS5
    const sanitized = args.name.replace(/[^\w*]/g, "");
    if (!sanitized) {
        db.close();
        return "Invalid search term";
    }
    // Use FTS5 for search — add wildcard for prefix matching
    const ftsQuery = sanitized.endsWith("*") ? sanitized : `${sanitized}*`;
    let results;
    if (args.kind) {
        results = db
            .prepare(`SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
                f.path, ps.name as parent_name
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         LEFT JOIN symbols ps ON s.parent_id = ps.id
         WHERE symbols_fts MATCH ? AND s.kind = ?
         ORDER BY rank
         LIMIT 30`)
            .all(ftsQuery, args.kind);
    }
    else {
        results = db
            .prepare(`SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
                f.path, ps.name as parent_name
         FROM symbols_fts fts
         JOIN symbols s ON fts.rowid = s.id
         JOIN files f ON s.file_id = f.id
         LEFT JOIN symbols ps ON s.parent_id = ps.id
         WHERE symbols_fts MATCH ?
         ORDER BY rank
         LIMIT 30`)
            .all(ftsQuery);
    }
    db.close();
    if (results.length === 0) {
        return `No symbols found matching "${args.name}"`;
    }
    const lines = [`Found ${results.length} match(es) for "${args.name}":`];
    for (const r of results) {
        const exported = r.exported ? " [exported]" : "";
        const parent = r.parent_name ? ` in ${r.parent_name}` : "";
        const sig = r.signature ? ` — ${r.signature}` : "";
        lines.push(`  ${r.kind} ${r.name}${parent}${exported}`);
        lines.push(`    ${r.path}:${r.line}${sig}`);
    }
    return lines.join("\n");
}
function handleFindUsages(args) {
    const db = openReadonly();
    // Find files that import this symbol
    const results = db
        .prepare(`SELECT f.path, i.symbols
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.symbols LIKE ?
       ORDER BY f.path
       LIMIT 50`)
        .all(`%${args.name}%`);
    db.close();
    if (results.length === 0) {
        return `No files import "${args.name}"`;
    }
    const lines = [`${results.length} file(s) import "${args.name}":`];
    for (const r of results) {
        lines.push(`  ${r.path} — imports: ${r.symbols ?? "(default)"}`);
    }
    return lines.join("\n");
}
function handleFileOverview(args) {
    const db = openReadonly();
    const file = db
        .prepare("SELECT id, language, size FROM files WHERE path = ?")
        .get(args.path);
    if (!file) {
        db.close();
        return `File not found in index: ${args.path}`;
    }
    const symbols = db
        .prepare(`SELECT s.name, s.kind, s.line, s.end_line, s.signature, s.exported,
              ps.name as parent_name
       FROM symbols s
       LEFT JOIN symbols ps ON s.parent_id = ps.id
       WHERE s.file_id = ?
       ORDER BY s.line`)
        .all(file.id);
    const imports = db
        .prepare("SELECT source, symbols FROM imports WHERE file_id = ? ORDER BY source")
        .all(file.id);
    db.close();
    const lines = [
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
function handleRelatedFiles(args) {
    const db = openReadonly();
    const file = db
        .prepare("SELECT id FROM files WHERE path = ?")
        .get(args.path);
    if (!file) {
        db.close();
        return `File not found in index: ${args.path}`;
    }
    // Files this file imports from
    const importsFrom = db
        .prepare(`SELECT i.source, i.symbols
       FROM imports i
       WHERE i.file_id = ?
       ORDER BY i.source`)
        .all(file.id);
    // Files that import from this file (by matching import source to this file's path)
    const basename = args.path.replace(/\.(ts|tsx|js|jsx|mjs|cjs)$/, "");
    const importedBy = db
        .prepare(`SELECT f.path, i.source, i.symbols, 'imported_by' as direction
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.source LIKE ? OR i.source LIKE ? OR i.source LIKE ?
       ORDER BY f.path
       LIMIT 30`)
        .all(`%${path.basename(basename)}`, `%/${basename}`, `./${basename}`);
    db.close();
    const lines = [`## Related files for ${args.path}`, ""];
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
export async function startMcpServer() {
    const server = new Server({ name: "codebase-pilot", version: "1.0.0" }, { capabilities: { tools: {} } });
    server.setRequestHandler(ListToolsRequestSchema, async () => ({
        tools: TOOLS,
    }));
    server.setRequestHandler(CallToolRequestSchema, async (request) => {
        const { name, arguments: args } = request.params;
        try {
            let result;
            switch (name) {
                case "project_map":
                    result = handleProjectMap();
                    break;
                case "find_symbol":
                    result = handleFindSymbol(args);
                    break;
                case "find_usages":
                    result = handleFindUsages(args);
                    break;
                case "file_overview":
                    result = handleFileOverview(args);
                    break;
                case "related_files":
                    result = handleRelatedFiles(args);
                    break;
                default:
                    result = `Unknown tool: ${name}`;
            }
            return {
                content: [{ type: "text", text: result }],
            };
        }
        catch (error) {
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
//# sourceMappingURL=mcp-server.js.map