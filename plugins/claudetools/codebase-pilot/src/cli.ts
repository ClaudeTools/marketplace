#!/usr/bin/env node

import { indexProject } from "./indexer.js";
import {
  handleProjectMap,
  handleFindSymbol,
  handleFindUsages,
  handleFileOverview,
  handleRelatedFiles,
} from "./mcp-server.js";
import { startMcpServer } from "./mcp-server.js";

const USAGE_TEXT = `Usage: codebase-pilot <command> [options]

Commands:
  index [path]             Index a project (default: current directory)
  map [path]               Generate project map
  find-symbol <name>       Search for a symbol by name
  find-usages <name>       Find all files that import a symbol
  file-overview <path>     List all symbols defined in a file
  related-files <path>     Find files connected via imports
  mcp-server               Start MCP server (stdio)

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
  const stats = indexProject(pathArg);
  const summary = [
    `Indexed ${stats.indexedFiles} files (${stats.skippedFiles} unchanged, ${stats.removedFiles} removed)`,
    `${stats.totalSymbols} symbols, ${stats.totalImports} imports in ${stats.durationMs}ms`,
  ].join("\n");
  process.stderr.write(summary + "\n");
}

function runMap(): void {
  setProjectEnv();
  process.stdout.write(handleProjectMap());
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

function runMcpServer(): void {
  setProjectEnv();
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
  case "find-usages":
    runFindUsages();
    break;
  case "file-overview":
    runFileOverview();
    break;
  case "related-files":
    runRelatedFiles();
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
