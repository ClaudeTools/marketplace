# Repo Restructure - Private Dev Repo + Public Distribution Repo

## Goal

Split claudetools into two repos with automated sync:
- **Private repo** (`claudetools-dev` or keep current `claude-code` and make it private) - all source code, tests, training, docs, data
- **Public repo** (`claude-code` or `claudetools`) - only the distributable plugin files, auto-published via GitHub Actions

Users install from the public repo. You develop in the private repo. A GitHub Action syncs the plugin subdirectory on every push to main.

## Step 1: Restructure the current repo

Move all distributable plugin files into a `plugin/` subdirectory. Everything else stays at the repo root.

### Create plugin/ and move distributable files into it

```bash
mkdir -p plugin

# Plugin manifest
git mv .claude-plugin plugin/

# Hooks and hook scripts
git mv hooks plugin/

# Skills
git mv skills plugin/

# Agents
git mv agents plugin/

# Rules
git mv rules plugin/

# Settings/MCP config (if they exist at root)
git mv settings.json plugin/ 2>/dev/null || true
git mv .mcp.json plugin/ 2>/dev/null || true
```

### Move scripts selectively

Only the scripts that hooks.json references at runtime should go into `plugin/`. Read `hooks/hooks.json` to identify every script path, then move only those files.

```bash
mkdir -p plugin/scripts/lib

# Move all hook scripts referenced in hooks.json
# Example (adjust based on actual hooks.json content):
# git mv scripts/enforce-team-usage.sh plugin/scripts/
# git mv scripts/validate-code-changes.sh plugin/scripts/
# ... etc for every script referenced in hooks.json

# Move runtime libraries that hook scripts source
git mv scripts/lib/adaptive-weights.sh plugin/scripts/lib/
git mv scripts/lib/common.sh plugin/scripts/lib/
git mv scripts/lib/ensure-db.sh plugin/scripts/lib/
```

IMPORTANT: Read `plugin/hooks/hooks.json` after moving it. Find every `"command"` value. Each one references a script path like `${CLAUDE_PLUGIN_ROOT}/scripts/something.sh`. Make sure every referenced script exists inside `plugin/scripts/`.

### Create empty data directory

```bash
mkdir -p plugin/data
touch plugin/data/.gitkeep
```

### Move codebase-pilot if user-facing

If codebase-pilot is part of the distributed plugin (referenced by hooks or skills), move it:
```bash
git mv codebase-pilot plugin/
```

If it's dev-only infrastructure, leave it at root.

### Create a user-facing README inside plugin/

Create `plugin/README.md` with usage instructions for the plugin. This is what appears on the public repo.

## Step 2: Verify all paths resolve

After moving files, verify nothing is broken:

1. Check every `"command"` path in `plugin/hooks/hooks.json` resolves to a real file inside `plugin/`
2. Check every `source` statement in scripts inside `plugin/scripts/` resolves correctly
3. Check every `${CLAUDE_PLUGIN_ROOT}` reference in SKILL.md files makes sense relative to `plugin/`
4. Run `bash -n` on every .sh file inside `plugin/`
5. Test locally: `claude --plugin-dir ./plugin` to verify the plugin loads

## Step 3: Update test paths

All BATS and Vitest tests reference scripts at the repo root. After the move, these are inside `plugin/`. Update every test path.

Search and update:
```bash
grep -rn "scripts/" tests/ --include="*.bats" --include="*.sh" --include="*.ts" -l
grep -rn "hooks/" tests/ --include="*.bats" --include="*.sh" --include="*.ts" -l
grep -rn "skills/" tests/ --include="*.bats" --include="*.sh" --include="*.ts" -l
```

Every reference like `"$SCRIPT_DIR/../scripts/something.sh"` needs to become `"$SCRIPT_DIR/../plugin/scripts/something.sh"` or use a PROJECT_ROOT variable.

Better approach: define a `PLUGIN_ROOT` variable at the top of each test helper that points to the plugin/ directory, then use it throughout.

## Step 4: Update .gitignore

```gitignore
# Runtime data
*.db
*.db-shm
*.db-wal
plugin/data/metrics.db
plugin/logs/

# Dev artifacts
logs/
.docs/
claudetools-v3-*.md
node_modules/

# Training results
tests/golden/data/
tests/golden/results/
tests/golden/tasks/
tests/training/results/
```

## Step 5: Create the public repo

1. Create a new public repo on GitHub: `owenob1/claude-code` (or whatever the current public name is)
2. This repo will be populated automatically by the GitHub Action - do not manually push to it

## Step 6: Set up GitHub Actions auto-sync

Create `.github/workflows/publish-plugin.yml` in the private repo:

```yaml
name: Publish Plugin to Public Repo

on:
  push:
    branches: [main]
    paths:
      - 'plugin/**'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout private repo
        uses: actions/checkout@v4

      - name: Push plugin/ to public repo
        uses: cpina/github-action-push-to-another-repository@main
        env:
          API_TOKEN_GITHUB: ${{ secrets.PUBLIC_REPO_TOKEN }}
        with:
          source-directory: 'plugin'
          destination-github-username: 'owenob1'
          destination-repository-name: 'claude-code'
          target-branch: 'main'
          user-email: 'me@oweninnes.com'
          user-name: 'Owen Innes'
          commit-message: 'sync: update plugin from dev repo'
```

### Set up the secret

1. Go to GitHub > Settings > Developer Settings > Personal Access Tokens > Fine-grained tokens
2. Create a token with write access to the public repo (`owenob1/claude-code`)
3. Go to the private repo > Settings > Secrets and Variables > Actions
4. Add a secret called `PUBLIC_REPO_TOKEN` with the token value

## Step 7: Update marketplace.json

The marketplace.json (wherever it lives) needs to point to the PUBLIC repo, not the private one. The public repo IS the plugin root (since the Action pushes the contents of `plugin/` as the root of the public repo).

So marketplace source should be the public repo URL. No subdirectory needed - the public repo root IS the plugin.

## Step 8: Make the current repo private

Once the public repo is set up and the Action is tested:

1. Rename the current `claude-code` repo to `claudetools-dev` (or similar)
2. Make it private: GitHub repo > Settings > Danger Zone > Change visibility > Private
3. The new public `claude-code` repo takes over as the distribution endpoint

## Step 9: Test the full pipeline

1. Make a small change to a file inside `plugin/` in the private repo
2. Commit and push to main
3. Verify the GitHub Action runs and pushes to the public repo
4. Run `claude plugin update claudetools` and verify it picks up the change
5. Verify hooks fire correctly

## Step 10: Commit everything

```bash
git add -A
git commit -m "restructure: split into plugin/ subdirectory for automated public distribution

- Moved all distributable files into plugin/
- Added GitHub Actions workflow to sync plugin/ to public repo
- Updated test paths to reference plugin/ directory
- Private repo keeps tests, training, golden references, docs, data
- Public repo receives only clean plugin files automatically"
git push
```

## Summary

After this restructure:
- You work ONLY in the private repo
- Push to main triggers GitHub Action
- Action extracts plugin/ and pushes to public repo
- Users install from public repo via marketplace
- Training data, dev docs, metrics, golden test fixtures - all private
- Zero manual publishing steps
