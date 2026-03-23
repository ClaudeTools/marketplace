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
//# sourceMappingURL=handlers.js.map