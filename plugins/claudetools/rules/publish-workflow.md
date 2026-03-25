---
paths: ["**/*.md", "**/*.json", "**/*.sh", "**/*.js", "**/*.yml"]
---

# Publishing Workflow — Plugin vs Docs Site

There are TWO separate publishing pipelines. They are NOT the same thing.

## 1. Plugin Publishing (marketplace-dev → marketplace)

**Trigger:** Push to `main` on ClaudeTools/marketplace-dev touching `plugin/`, `plugins/`, or `.claude-plugin/`

**What it does:**
- Runs `.github/workflows/publish-marketplace.yml`
- rsync `plugin/` → `plugins/claudetools/`
- Auto-bumps version via conventional commits
- Copies `plugins/`, `.claude-plugin/marketplace.json`, and `README.md` into `public-out/`
- Pushes `public-out/` to ClaudeTools/marketplace (REPLACES entire repo)

**CRITICAL:** The publish workflow REPLACES the public repo contents. This means:
- `docs/` gets DELETED from the public repo on every publish
- `.github/workflows/deploy-docs.yml` gets DELETED
- Any file not in `public-out/` is GONE

**How to publish plugin changes:**
```bash
git push  # to marketplace-dev branch
gh pr create --repo ClaudeTools/marketplace-dev
gh pr merge <N> --repo ClaudeTools/marketplace-dev --squash --admin
# Publish workflow auto-triggers
```

## 2. Docs Site Publishing (separate from plugin)

**The docs site is an Astro Starlight app in `docs/`.**

**AFTER every plugin publish, you MUST manually push docs to the public repo:**
```bash
cd /tmp/marketplace-docs-push  # or clone fresh
git pull
# Copy docs from source
rm -rf docs/src
cp -r <worktree>/docs/src docs/src
cp <worktree>/docs/astro.config.mjs docs/
cp <worktree>/docs/package.json docs/
# Recreate deploy workflow (publish wipes it)
mkdir -p .github/workflows
# Copy deploy-docs.yml content (see below)
git add -A && git commit -m "docs: update" && git push
```

**The deploy workflow must exist at `.github/workflows/deploy-docs.yml`:**
```yaml
name: Deploy Docs
on:
  push:
    branches: [main]
    paths: ['docs/**']
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - working-directory: docs
        run: npm install
      - working-directory: docs
        run: npx astro build
      - uses: actions/upload-pages-artifact@v3
        with: { path: docs/dist }
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: { name: github-pages }
    steps:
      - uses: actions/deploy-pages@v4
```

**GitHub Pages must be set to "GitHub Actions" source** (not "Deploy from branch") in repo Settings → Pages.

## 3. Public README (also separate)

The root `README.md` on the public marketplace repo gets overwritten by the publish workflow from `marketplace-dev/README.md`. But this is the DEVELOPMENT repo README, not the plugin README.

**To update the public README with skill tables/badges:**
```bash
SHA=$(gh api repos/ClaudeTools/marketplace/contents/README.md --jq '.sha')
CONTENT=$(base64 -w 0 plugin/README.md)
gh api repos/ClaudeTools/marketplace/contents/README.md -X PUT \
  -f message="docs: update README" -f content="$CONTENT" -f sha="$SHA"
```

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| Docs 404 after publish | Publish workflow wiped `docs/` | Push docs to public repo again |
| Deploy workflow missing | Publish workflow wiped `.github/` | Push `deploy-docs.yml` again |
| `npm ci` fails | No `package-lock.json` | Use `npm install` not `npm ci` in workflow |
| README shows old names | Publish copied dev README | Push `plugin/README.md` via GitHub API |
| Pages shows old content | Deploy didn't trigger | `gh workflow run deploy-docs.yml --repo ClaudeTools/marketplace` |
| Zod v3/v4 conflict | Astro version too new | Pin `astro@5.7.0` and `zod@3.23.8` |
