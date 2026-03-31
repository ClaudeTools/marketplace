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

Then monitor CI:
```bash
gh pr checks [PR-number] --watch
```

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

Post-deploy: check health endpoint if available, report status.

### Phase 4: Documentation

If docs were changed:
```bash
# Reindex documentation
bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-manager/scripts/docs-reindex.sh
```

### Phase 5: Record

Save session context to memory for future sessions:
- What was built and why
- Key decisions made
- Deployment status

## Safety Net

If /ship is followed correctly, these validators should never fire:
- `session-stop-gate` Tier 1 — no uncommitted changes (pre-flight catches them)
- `session-stop-gate` Tier 2 — no weasel phrases (evidence-based reporting)
- `git-commits.sh` — committed properly with conventional messages
