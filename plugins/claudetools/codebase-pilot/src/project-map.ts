import path from "node:path";
import Database from "better-sqlite3";
import { getDbPath } from "./db.js";

interface LanguageStat {
  language: string;
  count: number;
}

interface DirectoryNode {
  name: string;
  children: DirectoryNode[];
  fileCount: number;
}

interface TopExport {
  name: string;
  kind: string;
  file: string;
  line: number;
}

export function generateProjectMap(projectRoot: string): string {
  const dbPath = getDbPath(projectRoot);
  const db = new Database(dbPath, { readonly: true });

  const projectName = path.basename(projectRoot);

  // Language breakdown
  const languages = db
    .prepare(
      "SELECT language, COUNT(*) as count FROM files GROUP BY language ORDER BY count DESC"
    )
    .all() as LanguageStat[];

  // Total file count
  const totalFiles = db
    .prepare("SELECT COUNT(*) as n FROM files")
    .get() as { n: number };

  // Total symbol count
  const totalSymbols = db
    .prepare("SELECT COUNT(*) as n FROM symbols")
    .get() as { n: number };

  // Directory structure (top 2 levels)
  const allPaths = db
    .prepare("SELECT path FROM files ORDER BY path")
    .all() as { path: string }[];

  const dirTree = buildDirectoryTree(allPaths.map((r) => r.path), 2);

  // Entry points — files likely to be main entry points
  const entryPointPatterns = [
    "index.ts",
    "index.tsx",
    "index.js",
    "main.ts",
    "main.js",
    "app.ts",
    "app.tsx",
    "server.ts",
    "worker.ts",
    "cli.ts",
  ];
  const entryPoints = db
    .prepare(
      `SELECT path FROM files WHERE ${entryPointPatterns
        .map(() => "path LIKE ?")
        .join(" OR ")} ORDER BY path`
    )
    .all(...entryPointPatterns.map((p) => `%/${p}`)) as { path: string }[];

  // Also check root-level entry points
  const rootEntries = db
    .prepare(
      `SELECT path FROM files WHERE ${entryPointPatterns
        .map(() => "path = ?")
        .join(" OR ")} ORDER BY path`
    )
    .all(...entryPointPatterns) as { path: string }[];

  const allEntries = [
    ...new Set([
      ...rootEntries.map((e) => e.path),
      ...entryPoints.map((e) => e.path),
    ]),
  ].slice(0, 8);

  // Key exports — exported functions/classes/types with most imports
  const topExports = db
    .prepare(
      `SELECT s.name, s.kind, f.path as file, s.line
       FROM symbols s
       JOIN files f ON s.file_id = f.id
       WHERE s.exported = 1 AND s.kind IN ('function', 'class', 'interface', 'type')
       ORDER BY s.kind, s.name
       LIMIT 15`
    )
    .all() as TopExport[];

  db.close();

  // Build the compact map
  const lines: string[] = [];
  lines.push(`# ${projectName}`);
  lines.push("");

  // Languages
  const langSummary = languages
    .map((l) => `${l.language}(${l.count})`)
    .join(" ");
  lines.push(`${totalFiles.n} files, ${totalSymbols.n} symbols | ${langSummary}`);
  lines.push("");

  // Structure
  lines.push("## Structure");
  lines.push("```");
  for (const line of renderTree(dirTree, "")) {
    lines.push(line);
  }
  lines.push("```");
  lines.push("");

  // Entry points
  if (allEntries.length > 0) {
    lines.push("## Entry Points");
    for (const entry of allEntries) {
      lines.push(`- ${entry}`);
    }
    lines.push("");
  }

  // Key exports
  if (topExports.length > 0) {
    lines.push("## Key Exports");
    for (const exp of topExports) {
      lines.push(`- ${exp.kind} \`${exp.name}\` (${exp.file}:${exp.line})`);
    }
    lines.push("");
  }

  return lines.join("\n");
}

function buildDirectoryTree(
  paths: string[],
  maxDepth: number
): DirectoryNode[] {
  const root = new Map<string, { files: number; subdirs: Map<string, number> }>();

  for (const filePath of paths) {
    const parts = filePath.split("/");
    if (parts.length === 1) {
      // Root-level file
      if (!root.has(".")) {
        root.set(".", { files: 0, subdirs: new Map() });
      }
      root.get(".")!.files++;
      continue;
    }

    const topDir = parts[0];
    if (!root.has(topDir)) {
      root.set(topDir, { files: 0, subdirs: new Map() });
    }
    const entry = root.get(topDir)!;
    entry.files++;

    if (parts.length > 2 && maxDepth > 1) {
      const subDir = parts[1];
      entry.subdirs.set(subDir, (entry.subdirs.get(subDir) ?? 0) + 1);
    }
  }

  const nodes: DirectoryNode[] = [];
  for (const [name, info] of root) {
    if (name === ".") continue;
    const children: DirectoryNode[] = [];
    for (const [subName, subCount] of info.subdirs) {
      children.push({ name: subName, children: [], fileCount: subCount });
    }
    children.sort((a, b) => a.name.localeCompare(b.name));
    nodes.push({ name, children, fileCount: info.files });
  }
  nodes.sort((a, b) => a.name.localeCompare(b.name));

  return nodes;
}

function renderTree(nodes: DirectoryNode[], prefix: string): string[] {
  const lines: string[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    const isLast = i === nodes.length - 1;
    const connector = isLast ? "└── " : "├── ";
    const childPrefix = isLast ? "    " : "│   ";

    let label = `${node.name}/`;
    if (node.children.length === 0) {
      label += ` (${node.fileCount} files)`;
    }
    lines.push(prefix + connector + label);

    if (node.children.length > 0) {
      for (const childLine of renderTree(node.children, prefix + childPrefix)) {
        lines.push(childLine);
      }
    }
  }
  return lines;
}
