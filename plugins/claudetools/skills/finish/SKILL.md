---
name: finish
description: >
  Complete a development branch — decide whether to merge, create PR, or cleanup.
  Ensures all quality gates pass before delivering. Use when implementation and
  review are done and you're ready to ship.
argument-hint: "[merge|pr|cleanup]"
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [merge, PR, shipping, delivery, branch]
---

# Finish Development Branch

> Before delivering, prove the work is ready. Tests pass, review is done, no
> uncommitted changes, branch is up to date.

## Pre-Flight Checklist

Run these checks before any merge or PR:

1. **All tests pass** — run the test suite, verify output
2. **No uncommitted changes** — `git status` is clean
3. **Branch is up to date** — `git pull --rebase origin main` (or base branch)
4. **No merge conflicts** — resolve if any
5. **Review is done** — code has been reviewed (by skill, agent, or human)

## Delivery Options

Present these to the user:

### Option 1: Merge to main
```bash
git checkout main
git merge --no-ff <branch> -m "feat: <description>"
git push origin main
```
Use when: small team, trunk-based development, already reviewed.

### Option 2: Create Pull Request
```bash
git push -u origin <branch>
gh pr create --title "<title>" --body "<description>"
```
Use when: team review needed, CI must pass, documentation trail wanted.

### Option 3: Cleanup (abandon)
```bash
git checkout main
git branch -d <branch>
```
Use when: work was exploratory, superseded, or abandoned.

## After Delivery

- If docs changed, run `/docs-manager reindex`
- If publishing a plugin, sync to `plugins/` and push
- Tell the user what was delivered and where
