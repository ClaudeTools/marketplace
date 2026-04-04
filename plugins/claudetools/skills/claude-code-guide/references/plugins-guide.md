# Plugins Guide

How to build and publish Claude Code plugins — from directory layout to CI publishing pipeline.

## Table of Contents

- [What a plugin is](#what-a-plugin-is)
- [Plugin structure](#plugin-structure)
- [plugin.json manifest](#pluginjson-manifest)
- [marketplace.json registry](#marketplacejson-registry)
- [Auto-versioning](#auto-versioning)
- [CI publishing pipeline](#ci-publishing-pipeline)
- [Development workflow](#development-workflow)
- [Plugin vs standalone extensions](#plugin-vs-standalone-extensions)
- [MCP server registration](#mcp-server-registration)
- [Conventional commit format](#conventional-commit-format)
- [Gotchas](#gotchas)
- [Verification checklist](#verification-checklist)
- [Cross-references](#cross-references)

---

## What a plugin is

A plugin is a publishable package that bundles multiple Claude Code extension types into a single versioned unit. A plugin can contain any combination of:

- **Hooks** — shell scripts invoked at session lifecycle points
- **Skills** — markdown-driven workflows with scripts and references
- **Agents** — agent definition files for specialized behavior
- **MCP servers** — tool servers registered with Claude Code

Individual extensions (a single hook, a single skill) cannot exist independently in the marketplace. They must be bundled within a plugin. The plugin provides the versioning, manifest metadata, and directory structure that the marketplace requires for installation and updates.

One plugin = one marketplace entry = one version number = one installation unit.

---

## Plugin structure

A plugin has two representations: the **source** directory where development happens, and the **published** directory that CI syncs to the public marketplace.

```
plugin/                              # Source (development)
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest
├── hooks/
│   └── hooks.json                   # Central hook configuration
├── scripts/
│   ├── lib/                         # Shared libraries
│   ├── validators/                  # Validator functions
│   └── *.sh                         # Hook implementation scripts
├── skills/
│   └── skill-name/
│       ├── SKILL.md
│       ├── scripts/
│       └── references/
├── agents/
│   └── agent-name.md
├── task-system/                     # MCP server
│   ├── server.js
│   └── start.sh
└── README.md

plugins/claudetools/                 # Published artifact (synced by CI)
└── (mirror of plugin/ — NEVER edit directly)
```

Key points:

- All development happens in `plugin/`. The `plugins/` directory is a build artifact.
- The `plugins/{name}/` directory is an exact mirror created by `rsync`. Direct edits there will be overwritten on the next sync.
- The plugin name (`claudetools`) must match the directory name under `plugins/` and the `name` field in `plugin.json`.

---

## plugin.json manifest

Every plugin requires a `plugin.json` at `.claude-plugin/plugin.json`. This manifest controls marketplace display, versioning, and configuration.

```json
{
  "name": "claudetools",
  "version": "3.4.2",
  "description": "Universal guardrail and quality system for Claude Code...",
  "author": {
    "name": "owenob1"
  },
  "license": "MIT",
  "keywords": ["guardrails", "hooks", "quality", "safety"],
  "mcpServers": {
    "task-system": {
      "command": "bash",
      "args": ["${CLAUDE_PLUGIN_ROOT}/task-system/start.sh"]
    }
  }
}
```

### Field reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin identifier. Must match the directory name under `plugins/`. Lowercase, hyphens allowed. |
| `version` | Yes | SemVer string (`X.Y.Z`). Auto-managed by CI — never set manually. |
| `description` | Yes | Marketplace display text. Shown in search results and plugin detail pages. |
| `author` | Yes | Object with a `name` field. Identifies the publisher. |
| `license` | No | SPDX license identifier (e.g., `MIT`, `Apache-2.0`). |
| `keywords` | No | Array of strings used for marketplace discovery and search. |
| `mcpServers` | No | Map of MCP server names to their launch configuration. See [MCP server registration](#mcp-server-registration). |

---

## marketplace.json registry

The marketplace registry at `.claude-plugin/marketplace.json` lists every plugin published from this repository.

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "claudetools",
  "version": "1.1.0",
  "description": "Claude Code plugins by ClaudeTools...",
  "owner": {
    "name": "ClaudeTools",
    "email": "me@oweninnes.com"
  },
  "plugins": [
    {
      "name": "claudetools",
      "source": "./plugins/claudetools",
      "description": "Comprehensive guardrail system...",
      "version": "3.4.2",
      "category": "developer-tools",
      "tags": ["guardrails", "hooks", "safety", "quality"]
    },
    {
      "name": "sequential-thinking",
      "source": "./plugins/sequential-thinking",
      "description": "Sequential thinking MCP server...",
      "version": "1.1.0",
      "category": "developer-tools",
      "tags": ["thinking", "reasoning", "mcp"]
    }
  ]
}
```

### Top-level fields

| Field | Description |
|-------|-------------|
| `$schema` | Schema URL for validation. |
| `name` | Repository/organization name. |
| `version` | Registry format version (not individual plugin versions). |
| `description` | Repository-level description. |
| `owner` | Object with `name` and optional `email`. |
| `plugins` | Array of plugin entries. |

### Plugin entry fields

| Field | Description |
|-------|-------------|
| `name` | Plugin name. Must match plugin.json `name` and directory name. |
| `source` | Path to the published plugin directory, relative to the repo root. |
| `description` | Plugin-specific description for marketplace listing. |
| `version` | Current version. Must match plugin.json version (kept in sync by CI). |
| `category` | Marketplace category. Currently recognized: `developer-tools`. |
| `tags` | Array of discovery tags. |

---

## Auto-versioning

The `auto-version.sh` CI script handles all version management. It runs on every push to main and determines the appropriate bump from commit messages.

1. Reads all conventional commits since the last `chore: auto-bump` commit
2. Determines the highest-priority bump level across those commits
3. Updates the version in both `plugin.json` and `marketplace.json`
4. Generates a `CHANGELOG.md` entry for the plugin
5. Creates a `chore: auto-bump pluginname@X.Y.Z` commit
6. Skips entirely if the last commit is already an auto-bump (loop prevention)

### Bump levels

| Level | Triggers | Version effect |
|-------|----------|----------------|
| **MAJOR** | `BREAKING CHANGE` in commit body/footer, `!` suffix on type (e.g., `feat!:`), `[breaking]` tag | Increments major, resets minor and patch to 0 |
| **MINOR** | `feat:` or `feat(scope):` | Increments minor, resets patch to 0 |
| **PATCH** | Everything else: `fix:`, `chore:`, `docs:`, `refactor:`, `perf:`, `test:`, etc. | Increments patch only |

### Examples

```
feat: add validation scripts to claude-code-guide skill    → MINOR (3.4.0 → 3.5.0)
fix: action field review feedback for frontend-design      → PATCH (3.4.1 → 3.4.2)
feat!: redesign hook dispatcher pipeline                   → MAJOR (3.4.2 → 4.0.0)
chore: update README                                       → PATCH (3.4.2 → 3.4.3)
```

The cardinal rule: **never change version numbers manually**. The CI script owns all version changes.

---

## CI publishing pipeline

The publishing workflow at `.github/workflows/publish-marketplace.yml` handles the full path from source to public marketplace.

1. **Trigger** — fires on push to main when files change in `.claude-plugin/`, `plugins/`, or `plugin/`
2. **Auto-version** — runs `auto-version.sh` to bump versions based on conventional commits
3. **Commit back** — pushes version bump commits back to the dev repository
4. **Prepare output** — assembles `public-out/` with `marketplace.json` and `plugins/` directories
5. **Publish** — pushes the prepared output to the public marketplace repository using `PUBLIC_REPO_TOKEN`

### Token management

The pipeline authenticates using a GitHub token stored as a repository secret. This token expires frequently — refresh before publishing:

```bash
gh secret set PUBLIC_REPO_TOKEN --repo ClaudeTools/marketplace-dev --body "$(gh auth token)"
```

If publishing fails with authentication errors, a stale token is the most likely cause.

---

## Development workflow

1. **Develop** in `plugin/` — all source changes go here, never in `plugins/`
2. **Test** with `bats tests/bats/hooks/` and `cd tests && npm test`
3. **Sync** to published directory:
   ```bash
   rsync -a --delete --exclude='.git' --exclude='node_modules' --exclude='logs/' plugin/ plugins/claudetools/
   ```
   Use `rsync -n` (dry run) first to preview changes.
4. **Commit** with conventional commit format (see [below](#conventional-commit-format))
5. **Push to main** — CI handles auto-versioning, changelog generation, and marketplace publishing

---

## Plugin vs standalone extensions

Individual extensions cannot be published independently — they must live inside a plugin:

| Aspect | Plugin | Standalone Extension |
|--------|--------|---------------------|
| Scope | Complete package bundling multiple extension types | Single hook, skill, agent, or MCP server |
| Versioning | Single version across all components, auto-managed by CI | No independent version — shares the plugin version |
| Marketplace entry | One entry per plugin in marketplace.json | Not independently listed |
| Installation | `claude plugin install owner/name` | Installed as part of its parent plugin |
| Directory | `plugin/` source, `plugins/{name}/` published | Within the plugin's `skills/`, `hooks/`, `agents/`, or MCP dirs |
| Updates | Whole plugin updates atomically | Updated when the parent plugin version bumps |

---

## MCP server registration

Plugins can bundle MCP servers that provide additional tools to Claude Code. Servers are registered in the `mcpServers` field of `plugin.json`:

```json
{
  "mcpServers": {
    "task-system": {
      "command": "bash",
      "args": ["${CLAUDE_PLUGIN_ROOT}/task-system/start.sh"]
    }
  }
}
```

- **Key** (`task-system`) — becomes the tool prefix. Tools appear as `mcp__plugin_pluginname_task-system__toolname`.
- **command** — the executable to launch the server (`bash`, `node`, etc.).
- **args** — arguments passed to the command. Always use `${CLAUDE_PLUGIN_ROOT}` for paths.

The `${CLAUDE_PLUGIN_ROOT}` variable resolves to the installed plugin's absolute path at runtime. Hardcoded paths break on other machines.

MCP servers should use a start script that `cd`s into its own directory and `exec`s the server process for clean signal handling. See [MCP Servers Guide](mcp-servers-guide.md) for full details.

---

## Conventional commit format

All commits must follow conventional commit format. The auto-versioning system depends on this to determine version bumps.

Format: `type(optional-scope): description`

| Type | Purpose | Bump level |
|------|---------|------------|
| `feat` | New feature or capability | MINOR |
| `fix` | Bug fix | PATCH |
| `chore` | Maintenance, dependencies, tooling | PATCH |
| `docs` | Documentation changes | PATCH |
| `refactor` | Code restructuring without behavior change | PATCH |
| `perf` | Performance improvement | PATCH |
| `test` | Test additions or changes | PATCH |
| `feat!` | Breaking feature change | MAJOR |

Three ways to signal a breaking change (any triggers MAJOR): append `!` to the type (`feat!:`), include `BREAKING CHANGE` in the commit body/footer, or add `[breaking]` tag.

---

## Gotchas

1. **Never edit files in `plugins/` directly.** The published directory is synced from `plugin/` by rsync. Any direct edits will be silently overwritten on the next sync.

2. **Never change versions manually.** The `auto-version.sh` script handles all version bumps via conventional commits. Manual version changes will cause conflicts with the next auto-bump.

3. **PUBLIC_REPO_TOKEN expires frequently.** Always refresh via `gh secret set PUBLIC_REPO_TOKEN --repo ClaudeTools/marketplace-dev --body "$(gh auth token)"` before every publish cycle.

4. **Auto-bump loop prevention.** The auto-version script skips if the last commit starts with `chore: auto-bump`. This prevents infinite CI loops. Do not manually create commits with this prefix.

5. **Rsync excludes `.git`, `node_modules`, `logs/`.** These directories must never appear in published plugins. If you add new directories that should be excluded, update the rsync command.

6. **MCP server paths must use `${CLAUDE_PLUGIN_ROOT}`.** Hardcoded absolute paths will break when the plugin is installed on other machines. Always use the path variable.

7. **The `source` field in marketplace.json is relative to the repo root.** It points to the published directory (e.g., `./plugins/claudetools`), not relative to the manifest file itself.

8. **Category must be a recognized marketplace category.** Currently the only recognized category is `developer-tools`. Using an unrecognized category will cause validation failures.

9. **Plugin name must match across three locations.** The `name` in `plugin.json`, the `name` in the marketplace.json plugin entry, and the directory name under `plugins/` must all be identical.

10. **The marketplace.json version is the registry format version.** It is separate from individual plugin versions. Do not confuse the top-level `version` field with plugin versions listed in the `plugins` array.

---

## Verification checklist

Before pushing to main, verify the following:

- [ ] `.claude-plugin/plugin.json` exists with `name`, `version`, and `description` fields
- [ ] Version is valid semver (`X.Y.Z`) — three numeric segments separated by dots
- [ ] Plugin `name` matches the directory name under `plugins/`
- [ ] `marketplace.json` lists the plugin with a matching version
- [ ] MCP server entries in `plugin.json` reference start scripts that exist
- [ ] No `node_modules/` or `logs/` directories inside the plugin source
- [ ] All commit messages follow conventional commit format
- [ ] `PUBLIC_REPO_TOKEN` is fresh (refresh if publishing)
- [ ] Rsync dry run shows expected changes: `rsync -n -a --delete --exclude='.git' --exclude='node_modules' --exclude='logs/' plugin/ plugins/claudetools/`
- [ ] `README.md` exists in the plugin root
- [ ] Plugin name is consistent across `plugin.json`, `marketplace.json`, and directory name

---

## Cross-references

- [Skills Guide](skills-guide.md) — building skills within a plugin
- [Hooks Guide](hooks-guide.md) — building hooks within a plugin
- [Agents Guide](agents-guide.md) — building agent definitions within a plugin
- [MCP Servers Guide](mcp-servers-guide.md) — building MCP servers within a plugin
