---
name: docs-manager
description: >
  Manage project documentation with standardized structure, auditing, archiving,
  and index generation. Use when asked to organize docs, check for stale
  documentation, generate a docs index, or set up a docs directory.
argument-hint: "[audit|reindex|archive|init]"
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: documentation
  tags: [docs, documentation, index, audit, archive]
---

# /docs-manager — Documentation Governance

> Every project deserves maintained documentation. Stale docs are worse than no docs —
> they actively mislead. This skill ensures documentation stays structured, current, and honest.

## Frontmatter Schema

Every documentation file managed by this skill follows an industry-standard frontmatter schema
based on conventions from Jekyll, Hugo, Docusaurus, and GitHub Docs.

### Required Fields

```yaml
title: Authentication Flow          # Descriptive, not generic
description: How OAuth2 works E2E   # One-line summary, 10+ characters
updated: 2026-04-08                 # ISO date, not future, within 90 days
```

### Recommended Fields

```yaml
status: active                      # draft | active | review | deprecated
type: reference                     # guide | reference | decision | tutorial | overview | changelog | api | runbook
author: Jane Smith                  # Maintenance ownership
tags: [auth, oauth, security]       # Categorization for search and filtering
```

See `${CLAUDE_SKILL_DIR}/references/docs-quality-checklist.md` for the complete schema with
validation rules, type guide, and status lifecycle.

## When to Use

- Setting up docs for a new project or module
- After completing a feature — verify docs reflect the change
- Before shipping — audit doc quality as part of pre-flight
- When docs feel stale or disorganized
- When the `doc-index` session-end validator reports issues
- After `/ship` — the ship skill calls reindex automatically

## Why This Matters

| Rationalization | Reality |
|----------------|---------|
| "I'll document it later" | Later never comes. Document alongside the code. |
| "The code is self-documenting" | It explains *what*, not *why* or *how to use it*. |
| "Nobody reads the docs" | Nobody reads *bad* docs. Good docs get read. |
| "It's just a small change" | Small undocumented changes compound into large confusion. |

## Commands

### `init` — Set up documentation structure

Run when a project has no docs/ directory or needs new subdirectories.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-init.sh
```

**What it does:**
1. Checks if docs/ already exists — reports current structure if so
2. Creates docs/ with subdirectories (default: guides/, reference/, decisions/)
3. Generates index.md and _template.md in each directory
4. Creates docs/archive/ for deprecated documents

**Custom directories:** Pass space-separated names to override defaults:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-init.sh "api tutorials architecture"
```

**After init:** Tell the user what was created and suggest they start with the most important doc.

### `audit` — Check documentation quality

Run to find stale, broken, or incomplete documentation.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-audit.sh
```

**What it does:**
1. Scans all docs/ directories in the project
2. Validates each .md file against the frontmatter schema:
   - **Required fields:** title (not generic), description (10+ chars), updated (ISO date, not future, within 90 days)
   - **Recommended fields:** status (valid enum), author, type (valid enum), tags
   - **File quality:** kebab-case naming, non-empty content
3. Reports issues with severity levels: ERROR (must fix), WARNING (should fix), INFO (best practice)

See `${CLAUDE_SKILL_DIR}/examples/audit-output.md` for example output.
See `${CLAUDE_SKILL_DIR}/references/docs-quality-checklist.md` for the quality standards.

**After the audit script runs:**

If issues are found, present them grouped by severity. Then use AskUserQuestion to let the user choose which to fix:

```
AskUserQuestion:
  question: "Found N issues across M files. Which should I fix?"
  multiSelect: true
  header: "Doc fixes"
  options:
    - label: "Fix required fields (X files)"
      description: "Add missing title, description, updated to front matter"
    - label: "Add recommended fields (Y files)"
      description: "Add status, type, author, tags where missing"
    - label: "Update stale dates (Z files)"
      description: "Files not updated in 90+ days — review and update dates"
    - label: "Fix naming (W files)"
      description: "Rename files to kebab-case, update internal links"
    - label: "Fix invalid values (V files)"
      description: "Correct invalid status or type values"
```

For each selected fix:
- **Missing required front matter:** Read the file content, generate appropriate title/description from the content, add front matter block with today's date
- **Missing recommended fields:** Infer type from directory (guides/ → guide, reference/ → reference, decisions/ → decision). Detect author from git blame. Add empty tags array as placeholder.
- **Stale dates:** Update `updated:` to today. If the content itself looks stale (references old APIs, outdated instructions), flag it for the user to review rather than silently updating the date
- **Naming issues:** Rename the file to kebab-case and update any internal links that reference it
- **Invalid values:** Replace with the closest valid enum value or ask the user

Re-run the audit after fixes to confirm resolution.

### `reindex` — Regenerate documentation indexes

Run to update all docs/index.md files from frontmatter.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-reindex.sh
```

**What it does:**
1. Finds all docs/ directories in the project
2. For each directory (including subdirectories), reads .md file frontmatter
3. Generates a markdown table in index.md with: Document, Type, Description, Updated
4. Lists subdirectories with links to their own index.md (type: section)
5. Excludes deprecated documents from the index (status: deprecated)
6. Generates proper frontmatter on index.md files (title, description, updated, status, type)

**After reindex:** Report how many index files were updated.

Note: Reindexing also runs automatically at session end via the `doc-index` validator. Use this command for on-demand updates.

### `archive` — Move deprecated documents

Run to move documents marked `status: deprecated` to docs/archive/.

```bash
# Dry run (default) — shows what would be archived
bash ${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh

# Actually archive
bash ${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh --execute
```

**What it does:**
1. Scans all docs/ for files with `status: deprecated` in front matter
2. In dry-run mode (default): reports candidates without moving anything
3. With --execute: moves files to docs/archive/, preserving directory structure

**After the dry-run script runs:**

If candidates are found, present the list and confirm before archiving:

```
AskUserQuestion:
  question: "Found N deprecated docs. Archive them?"
  options:
    - label: "Archive all"
      description: "Move all N deprecated docs to docs/archive/"
    - label: "Choose which to archive"
      description: "I'll select specific docs to archive"
    - label: "Skip"
      description: "Leave them in place for now"
```

If "Archive all": run the script with --execute, then run reindex.
If "Choose which": present individual docs as multiSelect, move only selected ones manually.

## Integration with /design -> /build -> /ship

This skill is a natural companion to the workflow:
- **After /design:** Run `init` if the project lacks a docs/ directory. Document the design decisions in docs/decisions/.
- **During /build:** Update docs alongside code changes — don't defer.
- **Before /ship:** Run `audit` as part of pre-flight. The ship skill calls `reindex` automatically in Phase 4.

## Hook-Based Enforcement

Documentation standards are enforced automatically through 3 hooks — no manual invocation needed:

### 1. SessionStart: `doc-stale-detector.sh`

Runs at the start of every session. Scans all docs/ files and warns about:
- Documents missing YAML frontmatter
- Documents missing required fields (title, description)
- Stale documents (updated >90 days ago)
- Deprecated documents (status: deprecated)

Output is injected as a system message so the model is aware of doc health from the start.

### 2. PostToolUse (Edit/Write): `doc-manager.sh`

Runs every time a file in docs/ is written or edited. Validates the full frontmatter schema:

**Errors (must fix):**
- Missing YAML frontmatter — includes a fix template in the warning
- Missing required fields (title, description)

**Warnings (should fix):**
- Generic/empty titles
- Short descriptions (<10 chars)
- Invalid status values (not in: draft, active, review, deprecated)
- Stale or future dates
- Non-kebab-case filenames

**Suggestions (best practice):**
- Missing recommended fields: status, type, author, tags

Also **auto-updates** the `updated:` field to today's date on every edit.

### 3. SessionEnd: `doc-index.sh` (validator)

Runs at session end. Regenerates all docs/index.md files from frontmatter. Ensures indexes stay current without manual intervention.

### Enforcement Philosophy

- Hooks **warn**, they don't **block**. Documentation issues should never lock out a session.
- Required field violations go to stderr — the model sees them and can fix them inline.
- Recommended field suggestions are advisory — they encourage best practices over time.
- The `updated:` auto-update ensures staleness tracking is always accurate.

## Safety Net

If /docs-manager is used correctly, these hooks should never fire:
- `doc-stale-detector` SessionStart — no stale docs to warn about
- `doc-manager` PostToolUse — frontmatter is always complete on write
- `doc-index` SessionEnd — indexes are already current from manual reindex
