import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { appendFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { getDbPath } from "./db.js";
import { generateProjectMap } from "./project-map.js";
// ESM __dirname polyfill
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// --- Structured logging ---
const LOG_DIR = path.resolve(process.env.CLAUDE_PLUGIN_ROOT ?? path.join(__dirname, "../.."), "logs");
const LOG_FILE = path.join(LOG_DIR, "codebase-pilot.log");
function log(event, detail, durationMs) {
    try {
        mkdirSync(LOG_DIR, { recursive: true });
        const ts = new Date().toISOString();
        const dur = durationMs !== undefined ? ` duration=${durationMs}ms` : "";
        appendFileSync(LOG_FILE, `${ts} | codebase-pilot | ${event} | ${detail}${dur}\n`);
    }
    catch {
        // Never let logging break queries
    }
}
export function escapeLike(input) {
    return input.replace(/[%_\\]/g, "\\$&");
}
function loadSessionContext() {
    const files = new Map();
    let lastCompactTs = 0;
    try {
        const projectRoot = getProjectRoot();
        const sessionIdsPath = path.join(projectRoot, ".codeindex", "session-ids");
        if (!fs.existsSync(sessionIdsPath))
            return { files, lastCompactTs };
        const sessionIds = fs.readFileSync(sessionIdsPath, "utf-8")
            .split("\n")
            .map((s) => s.trim())
            .filter((s) => s.length > 0);
        if (sessionIds.length === 0)
            return { files, lastCompactTs };
        for (const sessionId of sessionIds) {
            const readsFile = `/tmp/codebase-pilot-reads-${sessionId}.jsonl`;
            if (!fs.existsSync(readsFile))
                continue;
            const lines = fs.readFileSync(readsFile, "utf-8").split("\n");
            for (const line of lines) {
                if (!line.trim())
                    continue;
                try {
                    const entry = JSON.parse(line);
                    // Compact event (global)
                    if (entry.event === "compact" && entry.ts > lastCompactTs) {
                        lastCompactTs = entry.ts;
                        continue;
                    }
                    if (!entry.path)
                        continue;
                    const existing = files.get(entry.path) ?? { lastReadTs: 0, lastEditTs: 0 };
                    if (entry.event === "edit") {
                        if (entry.ts > existing.lastEditTs)
                            existing.lastEditTs = entry.ts;
                    }
                    else {
                        // Read event (or legacy entry without event field)
                        if (entry.ts > existing.lastReadTs)
                            existing.lastReadTs = entry.ts;
                    }
                    files.set(entry.path, existing);
                }
                catch { /* skip malformed lines */ }
            }
        }
    }
    catch { /* never break on context tracking errors */ }
    return { files, lastCompactTs };
}
function findFileContext(filePath, ctx) {
    // Direct match
    const direct = ctx.files.get(filePath);
    if (direct && direct.lastReadTs > 0)
        return direct;
    // Suffix match — reads store absolute paths, index stores relative
    for (const [p, entry] of ctx.files) {
        if (entry.lastReadTs === 0)
            continue;
        if (p.endsWith(`/${filePath}`) || filePath.endsWith(`/${p}`))
            return entry;
    }
    return null;
}
function contextTag(filePath, ctx) {
    const entry = findFileContext(filePath, ctx);
    if (!entry)
        return "";
    // Was read before compaction and not re-read since?
    if (ctx.lastCompactTs > 0 && entry.lastReadTs < ctx.lastCompactTs) {
        return " [was read]";
    }
    // Check file mtime against read timestamp
    try {
        const projectRoot = getProjectRoot();
        const absPath = path.join(projectRoot, filePath);
        const mtime = Math.floor(fs.statSync(absPath).mtimeMs / 1000);
        if (mtime <= entry.lastReadTs) {
            return " [in context]"; // unchanged since last read
        }
        // File modified since last read — was it Claude's edit?
        if (entry.lastEditTs > 0 && entry.lastEditTs >= entry.lastReadTs) {
            return " [in context, edited]"; // Claude edited, knows the changes
        }
        return ""; // externally modified — needs re-read
    }
    catch {
        return ""; // file may be deleted or inaccessible
    }
}
// --- Navigate: query-driven multi-channel search ---
const NAVIGATE_STOPWORDS = new Set([
    "a", "an", "the", "is", "it", "in", "on", "at", "to", "for", "of", "and",
    "or", "not", "but", "if", "do", "be", "as", "by", "so", "no", "up", "we",
    "my", "me", "he", "all", "can", "has", "had", "was", "are", "its", "get",
    "set", "new", "use", "how", "who", "why", "what", "when", "from", "with",
    "this", "that", "will", "been", "have", "each", "make", "like", "then",
    "them", "than", "into", "only", "also", "just", "more", "some", "file",
    "code", "find", "show", "list",
]);
export function handleNavigate(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    // Tokenize query (split camelCase, PascalCase, snake_case, paths)
    const tokens = args.query
        .replace(/([a-z])([A-Z])/g, "$1 $2") // camelCase → camel Case
        .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2") // HTTPServer → HTTP Server
        .toLowerCase()
        .split(/[\s_\-./]+/)
        .filter((t) => t.length >= 2 && !NAVIGATE_STOPWORDS.has(t));
    if (tokens.length === 0) {
        return "No searchable terms in query. Try more specific keywords.";
    }
    const sessionCtx = loadSessionContext();
    const scores = new Map();
    for (const token of tokens) {
        // Channel 1: FTS5 symbol name match
        const sanitized = token.replace(/[^\w*]/g, "");
        if (sanitized) {
            const ftsQuery = `${sanitized}*`;
            try {
                const symbolHits = db
                    .prepare(`SELECT s.name, s.kind, s.line, f.path,
                    CASE WHEN LOWER(s.name) = ? THEN 15 ELSE 10 END as pts
             FROM symbols_fts fts
             JOIN symbols s ON fts.rowid = s.id
             JOIN files f ON s.file_id = f.id
             WHERE symbols_fts MATCH ?
             LIMIT 20`)
                    .all(token, ftsQuery);
                for (const hit of symbolHits) {
                    const entry = scores.get(hit.path) ?? { score: 0, symbols: [] };
                    entry.score += hit.pts;
                    const desc = `${hit.kind} ${hit.name}:${hit.line}`;
                    if (!entry.symbols.includes(desc))
                        entry.symbols.push(desc);
                    scores.set(hit.path, entry);
                }
            }
            catch { /* skip FTS errors */ }
        }
        // Channel 2: File path substring match
        try {
            const safeToken = escapeLike(token);
            const pathHits = db
                .prepare(`SELECT DISTINCT path FROM files WHERE path LIKE ? ESCAPE '\\' LIMIT 15`)
                .all(`%${safeToken}%`);
            for (const hit of pathHits) {
                const entry = scores.get(hit.path) ?? { score: 0, symbols: [] };
                entry.score += 3;
                scores.set(hit.path, entry);
            }
        }
        catch { /* skip */ }
        // Channel 3: Import source match
        try {
            const safeToken = escapeLike(token);
            const importHits = db
                .prepare(`SELECT DISTINCT f.path FROM imports i
           JOIN files f ON i.file_id = f.id
           WHERE i.source LIKE ? ESCAPE '\\'
           LIMIT 15`)
                .all(`%${safeToken}%`);
            for (const hit of importHits) {
                const entry = scores.get(hit.path) ?? { score: 0, symbols: [] };
                entry.score += 1;
                scores.set(hit.path, entry);
            }
        }
        catch { /* skip */ }
    }
    if (scores.size === 0) {
        return `No results for "${args.query}"`;
    }
    // Context bonus: files already in context are "free" to reference — boost their ranking
    for (const [filePath, data] of scores) {
        const tag = contextTag(filePath, sessionCtx);
        if (tag === " [in context]" || tag === " [in context, edited]") {
            data.score += 5;
        }
        else if (tag === " [was read]") {
            data.score += 2;
        }
    }
    // Rank by score descending, take top 15
    const ranked = [...scores.entries()]
        .sort((a, b) => b[1].score - a[1].score)
        .slice(0, 15);
    const lines = [`Navigate: "${args.query}" — ${ranked.length} result(s)`, ""];
    for (const [filePath, data] of ranked) {
        const tag = contextTag(filePath, sessionCtx);
        const syms = data.symbols.length > 0 ? ` — ${data.symbols.join(", ")}` : "";
        lines.push(`  [${data.score}] ${filePath}${tag}${syms}`);
    }
    return lines.join("\n");
}
function getProjectRoot() {
    return process.env.CODEBASE_PILOT_PROJECT_ROOT ?? process.cwd();
}
// Lazy singleton database connection — avoids per-call open/close race conditions
let cachedDb = null;
let cachedDbPath = null;
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
        cachedDb.pragma("busy_timeout = 1000");
        cachedDbPath = dbPath;
        return cachedDb;
    }
    catch (err) {
        process.stderr.write(`codebase-pilot: failed to open database: ${err}\n`);
        log("db_error", `failed to open database: ${err}`);
        return null;
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
export function handleProjectMap() {
    const projectRoot = getProjectRoot();
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    return generateProjectMap(projectRoot, db);
}
export function handleFindSymbol(args) {
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
    const sessionCtx = loadSessionContext();
    const lines = [`Found ${results.length} match(es) for "${args.name}":`];
    for (const r of results) {
        const exported = r.exported ? " [exported]" : "";
        const parent = r.parent_name ? ` in ${r.parent_name}` : "";
        const sig = r.signature ? ` — ${r.signature}` : "";
        const tag = contextTag(r.path, sessionCtx);
        lines.push(`  ${r.kind} ${r.name}${parent}${exported}`);
        lines.push(`    ${r.path}:${r.line}${tag}${sig}`);
    }
    return lines.join("\n");
}
export function handleFindUsages(args) {
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
    const sessionCtx = loadSessionContext();
    const tag = contextTag(args.path, sessionCtx);
    const lines = [
        `## ${args.path}${tag}`,
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
    const sessionCtx = loadSessionContext();
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
            const tag = contextTag(dep.path, sessionCtx);
            lines.push(`  ${dep.path}${tag}${syms}`);
        }
        lines.push("");
    }
    if (importsFrom.length === 0 && importedBy.length === 0) {
        lines.push("No import relationships found for this file.");
    }
    return lines.join("\n");
}
// --- Dead code: exported symbols never imported anywhere ---
export function handleDeadCode() {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const start = Date.now();
    // Get all exported symbols
    const exported = db
        .prepare(`SELECT s.name, s.kind, f.path, s.line
       FROM symbols s JOIN files f ON s.file_id = f.id
       WHERE s.exported = 1
       ORDER BY f.path, s.line`)
        .all();
    // Get all imported symbol names
    const allImports = db
        .prepare(`SELECT DISTINCT symbols FROM imports WHERE symbols IS NOT NULL AND symbols != ''`)
        .all();
    const importedNames = new Set();
    for (const row of allImports) {
        for (const sym of row.symbols.split(",")) {
            const trimmed = sym.trim().replace(/^\* as /, "");
            if (trimmed)
                importedNames.add(trimmed);
        }
    }
    // Filter exported symbols not in any import list
    const dead = exported.filter((s) => !importedNames.has(s.name));
    const elapsed = Date.now() - start;
    log("dead_code", `found ${dead.length} unreferenced exports`, elapsed);
    if (dead.length === 0) {
        return "No dead exports found — all exported symbols are imported somewhere.";
    }
    const lines = [`${dead.length} exported symbol(s) never imported:`, ""];
    let currentFile = "";
    for (const d of dead) {
        if (d.path !== currentFile) {
            if (currentFile)
                lines.push("");
            lines.push(`  ${d.path}`);
            currentFile = d.path;
        }
        lines.push(`    L${d.line} ${d.kind} ${d.name}`);
    }
    return lines.join("\n");
}
// --- Change impact: what breaks if I change this symbol? ---
export function handleChangeImpact(args) {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const start = Date.now();
    // Find the symbol's file
    const symbolRow = db
        .prepare(`SELECT s.name, f.path FROM symbols s
       JOIN files f ON s.file_id = f.id
       WHERE s.name = ?
       LIMIT 1`)
        .get(args.symbol);
    if (!symbolRow) {
        return `Symbol "${args.symbol}" not found in index`;
    }
    // Find all files that import from the symbol's file
    const basename = symbolRow.path.replace(/\.(ts|tsx|js|jsx|mjs|cjs|py)$/, "");
    const safeBasename = escapeLike(path.basename(basename));
    const importers = db
        .prepare(`SELECT DISTINCT f.path, i.symbols
       FROM imports i JOIN files f ON i.file_id = f.id
       WHERE i.source LIKE ? ESCAPE '\\'
          OR i.source LIKE ? ESCAPE '\\'
       ORDER BY f.path`)
        .all(`%${safeBasename}`, `%/${escapeLike(basename)}`);
    // Separate test files from direct importers
    const testPattern = /\.(test|spec)\.|__tests__\//;
    const directImporters = [];
    const testFiles = [];
    for (const imp of importers) {
        if (testPattern.test(imp.path)) {
            testFiles.push(imp.path);
        }
        else {
            directImporters.push(imp.path);
        }
    }
    const elapsed = Date.now() - start;
    log("change_impact", `${args.symbol}: ${importers.length} importers`, elapsed);
    const lines = [
        `Change impact for "${args.symbol}" (defined in ${symbolRow.path}):`,
        "",
        `Direct importers (${directImporters.length}):`,
    ];
    for (const f of directImporters)
        lines.push(`  ${f}`);
    lines.push("", `Test files (${testFiles.length}):`);
    for (const f of testFiles)
        lines.push(`  ${f}`);
    lines.push("", `Total impact: ${importers.length} file(s)`);
    return lines.join("\n");
}
// --- Context budget: rank files by importance (most-imported first) ---
export function handleContextBudget() {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const start = Date.now();
    const results = db
        .prepare(`SELECT i.source, COUNT(*) as import_count
       FROM imports i
       GROUP BY i.source
       ORDER BY import_count DESC
       LIMIT 20`)
        .all();
    const elapsed = Date.now() - start;
    log("context_budget", `ranked ${results.length} sources`, elapsed);
    if (results.length === 0) {
        return "No import data found. Run `codebase-pilot index` first.";
    }
    const lines = ["Most-imported sources (read these first):", ""];
    for (const r of results) {
        lines.push(`  [${r.import_count}x] ${r.source}`);
    }
    return lines.join("\n");
}
// --- API surface: all exported symbols ---
export function handleApiSurface() {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const start = Date.now();
    const results = db
        .prepare(`SELECT s.name, s.kind, s.signature, f.path, s.line
       FROM symbols s JOIN files f ON s.file_id = f.id
       WHERE s.exported = 1
       ORDER BY f.path, s.line`)
        .all();
    const elapsed = Date.now() - start;
    log("api_surface", `found ${results.length} exports`, elapsed);
    if (results.length === 0) {
        return "No exported symbols found.";
    }
    const lines = [`${results.length} exported symbol(s):`, ""];
    let currentFile = "";
    for (const r of results) {
        if (r.path !== currentFile) {
            if (currentFile)
                lines.push("");
            lines.push(`  ${r.path}`);
            currentFile = r.path;
        }
        const sig = r.signature ? ` — ${r.signature}` : "";
        lines.push(`    L${r.line} ${r.kind} ${r.name}${sig}`);
    }
    return lines.join("\n");
}
// --- Circular deps: find circular import chains ---
export function handleCircularDeps() {
    const db = getDatabase();
    if (!db)
        return dbErrorMessage();
    const start = Date.now();
    // Build adjacency list: file path → imported sources
    const allImports = db
        .prepare(`SELECT f.path, i.source
       FROM imports i JOIN files f ON i.file_id = f.id`)
        .all();
    // Build file path set for resolving import sources
    const allFiles = db
        .prepare(`SELECT path FROM files`)
        .all();
    const fileSet = new Set(allFiles.map((f) => f.path));
    // Build adjacency map
    const graph = new Map();
    for (const imp of allImports) {
        const targets = graph.get(imp.path) ?? [];
        const resolved = resolveImportSource(imp.source, imp.path, fileSet);
        if (resolved) {
            targets.push(resolved);
        }
        graph.set(imp.path, targets);
    }
    // DFS cycle detection
    const cycles = [];
    const visited = new Set();
    const inStack = new Set();
    function dfs(node, chain) {
        if (cycles.length >= 20)
            return;
        if (inStack.has(node)) {
            const cycleStart = chain.indexOf(node);
            if (cycleStart !== -1) {
                cycles.push([...chain.slice(cycleStart), node]);
            }
            return;
        }
        if (visited.has(node))
            return;
        visited.add(node);
        inStack.add(node);
        chain.push(node);
        for (const dep of graph.get(node) ?? []) {
            dfs(dep, chain);
        }
        chain.pop();
        inStack.delete(node);
    }
    for (const file of graph.keys()) {
        dfs(file, []);
    }
    const elapsed = Date.now() - start;
    log("circular_deps", `found ${cycles.length} cycles`, elapsed);
    if (cycles.length === 0) {
        return "No circular import chains found.";
    }
    const lines = [`${cycles.length} circular import chain(s):`, ""];
    for (let i = 0; i < cycles.length; i++) {
        lines.push(`  Cycle ${i + 1}: ${cycles[i].join(" → ")}`);
    }
    return lines.join("\n");
}
function resolveImportSource(source, importerPath, fileSet) {
    if (!source.startsWith(".") && !source.startsWith("/"))
        return null;
    const importerDir = path.dirname(importerPath);
    const resolved = path.normalize(path.join(importerDir, source));
    const extensions = ["", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py"];
    for (const ext of extensions) {
        if (fileSet.has(resolved + ext))
            return resolved + ext;
    }
    for (const ext of [".ts", ".js", ".tsx", ".jsx"]) {
        const indexPath = path.join(resolved, "index" + ext);
        if (fileSet.has(indexPath))
            return indexPath;
    }
    return null;
}
// --- Doctor: health check ---
export function handleDoctor() {
    const lines = ["codebase-pilot doctor", ""];
    let overallStatus = "OK";
    // 1. SQLite check
    try {
        const testDb = new Database(":memory:");
        testDb.close();
        lines.push("  [OK] SQLite (better-sqlite3) loads correctly");
    }
    catch (err) {
        lines.push(`  [FAIL] SQLite: ${err instanceof Error ? err.message : err}`);
        lines.push("    Fix: npm rebuild better-sqlite3");
        overallStatus = "BROKEN";
    }
    // 2. Grammar check — verify grammar packages exist in node_modules
    const codebasePilotRoot = path.resolve(__dirname, "..");
    const grammars = [
        { name: "TypeScript", pkg: "tree-sitter-typescript" },
        { name: "JavaScript", pkg: "tree-sitter-javascript" },
        { name: "Python", pkg: "tree-sitter-python" },
    ];
    for (const g of grammars) {
        const pkgPath = path.join(codebasePilotRoot, "node_modules", g.pkg);
        if (fs.existsSync(pkgPath)) {
            lines.push(`  [OK] Grammar: ${g.name}`);
        }
        else {
            lines.push(`  [WARN] Grammar: ${g.name} — not installed`);
            if (overallStatus === "OK")
                overallStatus = "DEGRADED";
        }
    }
    // Check WASM grammars
    const wasmsDir = path.join(codebasePilotRoot, "node_modules", "tree-sitter-wasms", "out");
    if (fs.existsSync(wasmsDir)) {
        try {
            const wasmFiles = fs.readdirSync(wasmsDir).filter((f) => f.endsWith(".wasm"));
            lines.push(`  [OK] WASM grammars: ${wasmFiles.length} available`);
        }
        catch {
            lines.push("  [WARN] WASM grammars directory exists but unreadable");
        }
    }
    else {
        lines.push("  [INFO] WASM grammars: not installed (run download-grammars.sh for extra languages)");
    }
    // 3. Index check
    const projectRoot = getProjectRoot();
    const dbPath = getDbPath(projectRoot);
    if (fs.existsSync(dbPath)) {
        lines.push(`  [OK] Index exists at ${dbPath}`);
        // 4. Freshness check
        try {
            const db = getDatabase();
            if (db) {
                const fileCount = db.prepare("SELECT COUNT(*) as cnt FROM files").get().cnt;
                lines.push(`  [OK] Index contains ${fileCount} files`);
                const staleFiles = db
                    .prepare(`SELECT path, modified_at FROM files
             ORDER BY modified_at DESC LIMIT 5`)
                    .all();
                let staleCount = 0;
                for (const f of staleFiles) {
                    try {
                        const absPath = path.join(projectRoot, f.path);
                        const fileMtime = Math.floor(fs.statSync(absPath).mtimeMs / 1000);
                        if (fileMtime > f.modified_at)
                            staleCount++;
                    }
                    catch { /* file may be deleted */ }
                }
                if (staleCount > 0) {
                    lines.push(`  [WARN] ${staleCount} of ${staleFiles.length} sampled files modified since last index`);
                    lines.push("    Fix: codebase-pilot index");
                    if (overallStatus === "OK")
                        overallStatus = "DEGRADED";
                }
                else {
                    lines.push("  [OK] Index appears fresh");
                }
            }
        }
        catch (err) {
            lines.push(`  [WARN] Could not check freshness: ${err instanceof Error ? err.message : err}`);
        }
    }
    else {
        lines.push(`  [FAIL] No index found at ${dbPath}`);
        lines.push("    Fix: codebase-pilot index");
        overallStatus = "BROKEN";
    }
    lines.push("");
    lines.push(`Overall: ${overallStatus}`);
    if (overallStatus === "DEGRADED") {
        lines.push("  Some features may be unavailable. Run the suggested fixes above.");
    }
    else if (overallStatus === "BROKEN") {
        lines.push("  Core functionality unavailable. Run the suggested fixes above.");
    }
    return lines.join("\n");
}
//# sourceMappingURL=handlers.js.map