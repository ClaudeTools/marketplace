import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { appendFileSync, mkdirSync } from "node:fs";
import { getDbPath } from "./db.js";
import { generateProjectMap } from "./project-map.js";
// --- Structured logging for MCP server ---
const LOG_DIR = path.resolve(process.env.CLAUDE_PLUGIN_ROOT ?? path.join(__dirname, "../.."), "logs");
const MCP_LOG = path.join(LOG_DIR, "mcp.log");
function mcpLog(event, detail, durationMs) {
    try {
        mkdirSync(LOG_DIR, { recursive: true });
        const ts = new Date().toISOString();
        const dur = durationMs !== undefined ? ` duration=${durationMs}ms` : "";
        appendFileSync(MCP_LOG, `${ts} | codebase-pilot | ${event} | ${detail}${dur}\n`);
    }
    catch {
        // Never let logging break the server
    }
}
export function escapeLike(input) {
    return input.replace(/[%_\\]/g, "\\$&");
}
function getProjectRoot() {
    return process.env.CODEBASE_PILOT_PROJECT_ROOT ?? process.cwd();
}
// Lazy singleton database connection — avoids per-call open/close race conditions
let cachedDb = null;
let cachedDbPath = null;
// Simple LRU cache for query results (1-minute TTL, max 50 entries)
const queryCache = new Map();
const CACHE_TTL_MS = 60_000;
const CACHE_MAX_SIZE = 50;
function cachedQuery(key, fn) {
    const now = Date.now();
    const cached = queryCache.get(key);
    if (cached && cached.expires > now) {
        return cached.result;
    }
    const result = fn();
    // Evict oldest entries if at capacity
    if (queryCache.size >= CACHE_MAX_SIZE) {
        const firstKey = queryCache.keys().next().value;
        if (firstKey !== undefined)
            queryCache.delete(firstKey);
    }
    queryCache.set(key, { result, expires: now + CACHE_TTL_MS });
    return result;
}
function getDatabase() {
    const projectRoot = getProjectRoot();
    const dbPath = getDbPath(projectRoot);
    // Return cached connection if still open and pointing at the same path
    if (cachedDb && cachedDbPath === dbPath) {
        try {
            // Verify the connection is still usable
            cachedDb.prepare("SELECT 1").get();
            return cachedDb;
        }
        catch {
            // Connection broken — close and reopen
            try {
                cachedDb.close();
            }
            catch { /* ignore */ }
            cachedDb = null;
            cachedDbPath = null;
        }
    }
    // Check if the database file exists
    if (!fs.existsSync(dbPath)) {
        return null;
    }
    try {
        cachedDb = new Database(dbPath, { readonly: true });
        cachedDbPath = dbPath;
        return cachedDb;
    }
    catch (err) {
        process.stderr.write(`codebase-pilot: failed to open database: ${err}\n`);
        mcpLog("db_error", `failed to open database: ${err}`);
        return null;
    }
}
function closeDatabase() {
    if (cachedDb) {
        try {
            cachedDb.close();
        }
        catch { /* ignore */ }
        cachedDb = null;
        cachedDbPath = null;
    }
}
function dbErrorMessage() {
    const projectRoot = getProjectRoot();
    const dbPath = getDbPath(projectRoot);
    if (!fs.existsSync(dbPath)) {
        return `No codebase index found at ${projectRoot}. Run \`codebase-pilot index\` to create one.`;
    }
    return `Codebase index could not be opened. It may be corrupt or locked. Run \`codebase-pilot index\` to rebuild.`;
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
export function handleProjectMap() {
    const projectRoot = getProjectRoot();
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    return generateProjectMap(projectRoot, db);
}
export function handleFindSymbol(args) {
    const cacheKey = `find_symbol:${args.name}:${args.kind ?? ""}`;
    return cachedQuery(cacheKey, () => handleFindSymbolUncached(args));
}
function handleFindSymbolUncached(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    // Sanitize the search term for FTS5
    const sanitized = args.name.replace(/[^\w*]/g, "");
    if (!sanitized) {
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
export function handleFindUsages(args) {
    const cacheKey = `find_usages:${args.name}`;
    return cachedQuery(cacheKey, () => handleFindUsagesUncached(args));
}
function handleFindUsagesUncached(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    // Find files that import this symbol
    const safeName = escapeLike(args.name);
    const results = db
        .prepare(`SELECT f.path, i.symbols
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.symbols LIKE ? ESCAPE '\\'
       ORDER BY f.path
       LIMIT 50`)
        .all(`%${safeName}%`);
    if (results.length === 0) {
        return `No files import "${args.name}"`;
    }
    const lines = [`${results.length} file(s) import "${args.name}":`];
    for (const r of results) {
        lines.push(`  ${r.path} — imports: ${r.symbols ?? "(default)"}`);
    }
    return lines.join("\n");
}
export function handleFileOverview(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const file = db
        .prepare("SELECT id, language, size FROM files WHERE path = ?")
        .get(args.path);
    if (!file) {
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
export function handleRelatedFiles(args) {
    const cacheKey = `related_files:${args.path}`;
    return cachedQuery(cacheKey, () => handleRelatedFilesUncached(args));
}
function handleRelatedFilesUncached(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const file = db
        .prepare("SELECT id FROM files WHERE path = ?")
        .get(args.path);
    if (!file) {
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
    const safeBasename = escapeLike(path.basename(basename));
    const safeFullBasename = escapeLike(basename);
    const importedBy = db
        .prepare(`SELECT f.path, i.source, i.symbols, 'imported_by' as direction
       FROM imports i
       JOIN files f ON i.file_id = f.id
       WHERE i.source LIKE ? ESCAPE '\\' OR i.source LIKE ? ESCAPE '\\' OR i.source LIKE ? ESCAPE '\\'
       ORDER BY f.path
       LIMIT 30`)
        .all(`%${safeBasename}`, `%/${safeFullBasename}`, `./${safeFullBasename}`);
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
    // --- Process-level error handling ---
    // Ignore SIGPIPE — standard for stdio servers (client may disconnect)
    process.on("SIGPIPE", () => { });
    // Catch unhandled errors to prevent process crashes
    process.on("uncaughtException", (err) => {
        process.stderr.write(`codebase-pilot: uncaught exception: ${err}\n`);
    });
    process.on("unhandledRejection", (reason) => {
        process.stderr.write(`codebase-pilot: unhandled rejection: ${reason}\n`);
    });
    // Handle stdout write errors (EPIPE when client disconnects)
    process.stdout.on("error", (err) => {
        if (err.code === "EPIPE") {
            closeDatabase();
            process.exit(0);
        }
        process.stderr.write(`codebase-pilot: stdout error: ${err}\n`);
    });
    // Graceful shutdown on signals
    const shutdown = () => {
        closeDatabase();
        process.exit(0);
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
    // --- Server setup ---
    const server = new Server({ name: "codebase-pilot", version: "1.0.0" }, { capabilities: { tools: {} } });
    // Transport lifecycle handlers
    server.onerror = (err) => {
        process.stderr.write(`codebase-pilot: server error: ${err}\n`);
    };
    server.onclose = () => {
        closeDatabase();
        process.exit(0);
    };
    server.setRequestHandler(ListToolsRequestSchema, async () => ({
        tools: TOOLS,
    }));
    server.setRequestHandler(CallToolRequestSchema, async (request) => {
        const { name, arguments: args } = request.params;
        const callStart = Date.now();
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
            mcpLog("tool_call", `tool=${name} status=ok`, Date.now() - callStart);
            return {
                content: [{ type: "text", text: result }],
            };
        }
        catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            mcpLog("tool_error", `tool=${name} error=${message.slice(0, 200)}`, Date.now() - callStart);
            return {
                content: [{ type: "text", text: `Error: ${message}` }],
                isError: true,
            };
        }
    });
    const transport = new StdioServerTransport();
    await server.connect(transport);
    mcpLog("startup", `project=${getProjectRoot()} pid=${process.pid}`);
    // Detect client disconnect via stdin EOF
    process.stdin.on("end", () => {
        mcpLog("shutdown", "stdin EOF (client disconnected)");
        closeDatabase();
        process.exit(0);
    });
}
//# sourceMappingURL=mcp-server.js.map