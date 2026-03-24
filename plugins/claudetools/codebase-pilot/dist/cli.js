#!/usr/bin/env node
import { indexProject, indexSingleFile } from "./indexer.js";
import { handleProjectMap, handleFindSymbol, handleFindUsages, handleFileOverview, handleRelatedFiles, handleNavigate, handleDeadCode, handleChangeImpact, handleContextBudget, handleApiSurface, handleCircularDeps, handleDoctor, } from "./handlers.js";
const USAGE_TEXT = `Usage: codebase-pilot <command> [options]

Commands:
  index [path]             Index a project (default: current directory)
  index-file <path>        Re-index a single file (incremental)
  map [path]               Generate project map
  find-symbol <name>       Search for a symbol by name
  find-usages <name>       Find all files that import a symbol
  file-overview <path>     List all symbols defined in a file
  related-files <path>     Find files connected via imports
  navigate <query>         Query-driven search across symbols, paths, and imports
  dead-code                Find exported symbols never imported anywhere
  change-impact <symbol>   Show what breaks if a symbol changes
  context-budget           Rank files by import count (most-imported first)
  api-surface              List all exported symbols across the project
  circular-deps            Find circular import chains
  doctor                   Health check — SQLite, grammars, index freshness

Options:
  --kind <kind>            Filter find-symbol by kind
  --project <path>         Project root (default: cwd)`;
const cliArgs = process.argv.slice(2);
const command = cliArgs[0];
function getProjectRoot() {
    const pathIdx = cliArgs.indexOf("--project");
    if (pathIdx !== -1 && cliArgs[pathIdx + 1]) {
        return cliArgs[pathIdx + 1];
    }
    const cmdArgs = cliArgs.slice(1).filter((a) => !a.startsWith("--"));
    // For commands that take a name/path as first arg, don't use it as project root
    return process.cwd();
}
function getArg(index) {
    const arg = cliArgs[index];
    return arg && !arg.startsWith("--") ? arg : undefined;
}
function setProjectEnv() {
    const root = getProjectRoot();
    if (!process.env.CODEBASE_PILOT_PROJECT_ROOT) {
        process.env.CODEBASE_PILOT_PROJECT_ROOT = root;
    }
}
async function runIndex() {
    const pathArg = getArg(1) ?? process.cwd();
    try {
        const stats = await indexProject(pathArg);
        const summary = [
            `Indexed ${stats.indexedFiles} files (${stats.skippedFiles} unchanged, ${stats.removedFiles} removed)`,
            `${stats.totalSymbols} symbols, ${stats.totalImports} imports in ${stats.durationMs}ms`,
        ].join("\n");
        process.stderr.write(summary + "\n");
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`codebase-pilot index error: ${msg}\n`);
        process.exit(1);
    }
}
function runMap() {
    setProjectEnv();
    try {
        const output = handleProjectMap();
        process.stdout.write(output);
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`codebase-pilot map error: ${msg}\n`);
        process.exit(1);
    }
}
function runFindSymbol() {
    const name = getArg(1);
    if (!name) {
        process.stderr.write("Error: symbol name required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    setProjectEnv();
    const kindIdx = cliArgs.indexOf("--kind");
    const kind = kindIdx !== -1 ? cliArgs[kindIdx + 1] : undefined;
    process.stdout.write(handleFindSymbol({ name, kind }) + "\n");
}
function runFindUsages() {
    const name = getArg(1);
    if (!name) {
        process.stderr.write("Error: symbol name required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    setProjectEnv();
    process.stdout.write(handleFindUsages({ name }) + "\n");
}
function runFileOverview() {
    const filePath = getArg(1);
    if (!filePath) {
        process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    setProjectEnv();
    process.stdout.write(handleFileOverview({ path: filePath }) + "\n");
}
function runRelatedFiles() {
    const filePath = getArg(1);
    if (!filePath) {
        process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    setProjectEnv();
    process.stdout.write(handleRelatedFiles({ path: filePath }) + "\n");
}
async function runIndexFile() {
    const filePath = getArg(1);
    if (!filePath) {
        process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    const projectRoot = getProjectRoot();
    if (!process.env.CODEBASE_PILOT_PROJECT_ROOT) {
        process.env.CODEBASE_PILOT_PROJECT_ROOT = projectRoot;
    }
    const stats = await indexSingleFile(projectRoot, filePath);
    if (stats.deleted) {
        process.stderr.write(`Removed ${filePath} from index (${stats.durationMs}ms)\n`);
    }
    else {
        process.stderr.write(`Re-indexed ${filePath}: ${stats.symbols} symbols, ${stats.imports} imports (${stats.durationMs}ms)\n`);
    }
}
function runNavigate() {
    const query = getArg(1);
    if (!query) {
        process.stderr.write("Error: query required\n" + USAGE_TEXT + "\n");
        process.exit(1);
    }
    setProjectEnv();
    process.stdout.write(handleNavigate({ query }) + "\n");
}
async function main() {
    switch (command) {
        case "index":
            await runIndex();
            break;
        case "index-file":
            await runIndexFile();
            break;
        case "map":
            runMap();
            break;
        case "find-symbol":
            runFindSymbol();
            break;
        case "find-usages":
            runFindUsages();
            break;
        case "file-overview":
            runFileOverview();
            break;
        case "related-files":
            runRelatedFiles();
            break;
        case "navigate":
            runNavigate();
            break;
        case "dead-code":
            setProjectEnv();
            process.stdout.write(handleDeadCode() + "\n");
            break;
        case "change-impact":
            setProjectEnv();
            process.stdout.write(handleChangeImpact({ symbol: getArg(1) ?? "" }) + "\n");
            break;
        case "context-budget":
            setProjectEnv();
            process.stdout.write(handleContextBudget() + "\n");
            break;
        case "api-surface":
            setProjectEnv();
            process.stdout.write(handleApiSurface() + "\n");
            break;
        case "circular-deps":
            setProjectEnv();
            process.stdout.write(handleCircularDeps() + "\n");
            break;
        case "doctor":
            setProjectEnv();
            process.stdout.write(handleDoctor() + "\n");
            break;
        default:
            if (command) {
                process.stderr.write(`Unknown command: ${command}\n`);
            }
            process.stderr.write(USAGE_TEXT + "\n");
            process.exit(1);
    }
}
main().catch((err) => {
    process.stderr.write(`codebase-pilot error: ${err instanceof Error ? err.message : String(err)}\n`);
    process.exit(1);
});
//# sourceMappingURL=cli.js.map