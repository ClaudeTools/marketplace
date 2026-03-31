---
name: ship
description: >
  Ship the work — run code review, create PR, verify CI, merge or deploy.
  Third command in the /design → /build → /ship workflow. Ensures nothing ships
  without evidence it works.
argument-hint: "[merge|pr|deploy]"
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion, Agent
metadata:
  author: claudetools
  version: 2.0.0
  category: workflow
  tags: [ship, deploy, review, PR, CI, delivery, workflow]
---

# /ship — Review, Deliver, Deploy

> IRON LAW: Nothing ships without evidence. Tests must pass. Review must complete.
> CI must be green. "It should work" is not evidence.

## The Process

### Phase 1: Pre-flight

Before anything else, verify the work is ready:

```bash
# 1. Tests pass
[project test command]

# 2. No uncommitted changes
git status

# 3. No stubs or TODOs in changed files
git diff --name-only HEAD~[N] HEAD | xargs grep -l 'TODO\|FIXME\|NotImplementedError' || echo "Clean"

# 4. Branch is up to date
git pull --rebase origin main
```

If any check fails, fix it before proceeding. Do not skip.

### Phase 2: Code Review

Run the structured 4-pass review:

1. **Correctness** — Does the code do what it claims? Edge cases handled?
2. **Security** — Hardcoded secrets? Injection risks? Auth issues?
3. **Performance** — N+1 queries? Unnecessary allocations? Missing indexes?
4. **Maintainability** — Clear naming? Reasonable structure? Test coverage?

Report findings. If critical issues found, fix them before proceeding.

### Phase 3: Deliver

Present options via AskUserQuestion:

```
AskUserQuestion:
  question: "How do you want to deliver?"
  options:
    - label: "Create PR"
      description: "Push branch, create PR with structured description, wait for CI"
    - label: "Merge to main"
      description: "Merge directly (small team, already reviewed)"
    - label: "Deploy"
      description: "Create PR, merge when CI passes, deploy to production"
```

**If Create PR:**
```bash
git push -u origin [branch]
gh pr create --title "[title]" --body "$(cat <<'EOF'
## Summary
[2-3 bullet points from the plan]

## Test Plan
[What was tested and how]

## Changes
[File count and nature of changes]
EOF
)"
```

#### CI monitoring

After creating the PR, monitor CI until it completes:

```bash
# Watch all CI checks until done
gh pr checks [PR-number] --watch

# If a check fails, get the failure log
gh run view [run-id] --log-failed
```

**If CI fails:**
1. Read the failure log: `gh run view --log-failed`
2. Diagnose: is it a test failure, lint error, build error, or infra issue?
3. Fix locally, push, wait for re-run
4. Do NOT merge with failing CI — ever

**Common CI issues and how to diagnose them:**
- **Missing env vars** — check repository secrets (`gh secret list`); the job log will show which variable is undefined
- **Wrong Node/Python version** — compare `.nvmrc` or `pyproject.toml` against the CI config's `node-version` or `python-version`
- **Test timeout** — check if the test has a real infinite loop, or just needs a higher timeout in the CI config
- **Lint failure** — run the linter locally first (`npm run lint`, `ruff check .`) to reproduce before pushing a fix

Report: "PR #[N] created. CI: ✓ all checks passing. Ready to merge."

**If Merge:**
```bash
git checkout main
git merge --no-ff [branch] -m "feat: [description]"
git push origin main
```

**If Deploy:**
After PR merge, detect deployment platform:
- `wrangler.jsonc` → Cloudflare Workers: `npx wrangler deploy`
- `vercel.json` → Vercel: `npx vercel --prod`
- `Dockerfile` → Docker: `docker build && docker push`
- `fly.toml` → Fly.io: `fly deploy`

### Post-deploy verification

After deployment completes, verify the deploy is healthy before declaring done:

1. **Health check** — hit the health endpoint if one exists:
   ```bash
   curl -sf https://[deployed-url]/health || echo "UNHEALTHY"
   ```

2. **Smoke test** — verify the core feature works:
   - Can the main page load?
   - Does the API respond to a basic request?
   - Are logs showing normal traffic (not error spikes)?

3. **Monitor for 2 minutes** — watch for error spikes before declaring success:
   ```bash
   # Cloudflare Workers
   wrangler tail --format=pretty 2>/dev/null | head -20

   # Vercel / other platforms: check the dashboard for error rate
   ```

4. **If something's wrong** — rollback immediately, don't investigate in production:
   ```bash
   # Revert the merge commit
   git revert -m 1 HEAD
   git push origin main
   # Redeploy previous version using same deploy command
   ```
   After rollback, investigate the failure locally.

### Phase 4: Documentation

If docs were changed:
```bash
# Reindex documentation
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-reindex.sh
```

### Phase 5: Record

Save session context to memory for future sessions.

Key things to record:
- **What was built and why** — for project context in future sessions
- **Key decisions made** — architecture choices, tradeoffs accepted
- **Any gotchas discovered** — deployment quirks, env var requirements, flaky tests
- **Deployment configuration used** — which platform, which environment, which flags

The auto-memory system handles extraction automatically. For significant decisions,
call them out explicitly so extraction is reliable: "Saving to memory: chose streaming
over polling because of existing WebSocket infrastructure."

## Safety Net

If /ship is followed correctly, these validators should never fire:
- `session-stop-gate` Tier 1 — no uncommitted changes (pre-flight catches them)
- `session-stop-gate` Tier 2 — no weasel phrases (evidence-based reporting)
- `git-commits.sh` — committed properly with conventional messages
