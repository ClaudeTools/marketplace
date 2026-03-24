#!/usr/bin/env node

import { indexProject, indexSingleFile } from "./indexer.js";
import {
  handleProjectMap,
  handleFindSymbol,
  handleFindUsages,
  handleFileOverview,
  handleRelatedFiles,
  handleNavigate,
  handleDeadCode,
  handleChangeImpact,
  handleContextBudget,
  handleApiSurface,
  handleCircularDeps,
  handleDoctor,
} from "./handlers.js";

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

function getProjectRoot(): string {
  const pathIdx = cliArgs.indexOf("--project");
  if (pathIdx !== -1 && cliArgs[pathIdx + 1]) {
    return cliArgs[pathIdx + 1];
  }
  const cmdArgs = cliArgs.slice(1).filter((a: string) => !a.startsWith("--"));
  // For commands that take a name/path as first arg, don't use it as project root
  return process.cwd();
}

function getArg(index: number): string | undefined {
  const arg = cliArgs[index];
  return arg && !arg.startsWith("--") ? arg : undefined;
}

function setProjectEnv(): void {
  const root = getProjectRoot();
  if (!process.env.CODEBASE_PILOT_PROJECT_ROOT) {
    process.env.CODEBASE_PILOT_PROJECT_ROOT = root;
  }
}

function runIndex(): void {
  const pathArg = getArg(1) ?? process.cwd();
  try {
    const stats = indexProject(pathArg);
    const summary = [
      `Indexed ${stats.indexedFiles} files (${stats.skippedFiles} unchanged, ${stats.removedFiles} removed)`,
      `${stats.totalSymbols} symbols, ${stats.totalImports} imports in ${stats.durationMs}ms`,
    ].join("\n");
    process.stderr.write(summary + "\n");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`codebase-pilot index error: ${msg}\n`);
    process.exit(1);
  }
}

function runMap(): void {
  setProjectEnv();
  try {
    const output = handleProjectMap();
    process.stdout.write(output);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`codebase-pilot map error: ${msg}\n`);
    process.exit(1);
  }
}

function runFindSymbol(): void {
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

function runFindUsages(): void {
  const name = getArg(1);
  if (!name) {
    process.stderr.write("Error: symbol name required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  setProjectEnv();
  process.stdout.write(handleFindUsages({ name }) + "\n");
}

function runFileOverview(): void {
  const filePath = getArg(1);
  if (!filePath) {
    process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  setProjectEnv();
  process.stdout.write(handleFileOverview({ path: filePath }) + "\n");
}

function runRelatedFiles(): void {
  const filePath = getArg(1);
  if (!filePath) {
    process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  setProjectEnv();
  process.stdout.write(handleRelatedFiles({ path: filePath }) + "\n");
}

function runIndexFile(): void {
  const filePath = getArg(1);
  if (!filePath) {
    process.stderr.write("Error: file path required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  const projectRoot = getProjectRoot();
  if (!process.env.CODEBASE_PILOT_PROJECT_ROOT) {
    process.env.CODEBASE_PILOT_PROJECT_ROOT = projectRoot;
  }
  const stats = indexSingleFile(projectRoot, filePath);
  if (stats.deleted) {
    process.stderr.write(`Removed ${filePath} from index (${stats.durationMs}ms)\n`);
  } else {
    process.stderr.write(
      `Re-indexed ${filePath}: ${stats.symbols} symbols, ${stats.imports} imports (${stats.durationMs}ms)\n`
    );
  }
}

function runNavigate(): void {
  const query = getArg(1);
  if (!query) {
    process.stderr.write("Error: query required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  setProjectEnv();
  process.stdout.write(handleNavigate({ query }) + "\n");
}

function runDeadCode(): void {
  setProjectEnv();
  process.stdout.write(handleDeadCode() + "\n");
}

function runChangeImpact(): void {
  const symbol = getArg(1);
  if (!symbol) {
    process.stderr.write("Error: symbol name required\n" + USAGE_TEXT + "\n");
    process.exit(1);
  }
  setProjectEnv();
  process.stdout.write(handleChangeImpact({ symbol }) + "\n");
}

function runContextBudget(): void {
  setProjectEnv();
  process.stdout.write(handleContextBudget() + "\n");
}

function runApiSurface(): void {
  setProjectEnv();
  process.stdout.write(handleApiSurface() + "\n");
}

function runCircularDeps(): void {
  setProjectEnv();
  process.stdout.write(handleCircularDeps() + "\n");
}

function runDoctor(): void {
  setProjectEnv();
  process.stdout.write(handleDoctor() + "\n");
}

switch (command) {
  case "index":
    runIndex();
    break;
  case "index-file":
    runIndexFile();
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
    runDeadCode();
    break;
  case "change-impact":
    runChangeImpact();
    break;
  case "context-budget":
    runContextBudget();
    break;
  case "api-surface":
    runApiSurface();
    break;
  case "circular-deps":
    runCircularDeps();
    break;
  case "doctor":
    runDoctor();
    break;
  default:
    if (command) {
      process.stderr.write(`Unknown command: ${command}\n`);
    }
    process.stderr.write(USAGE_TEXT + "\n");
    process.exit(1);
}
