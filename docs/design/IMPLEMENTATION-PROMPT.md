# Implementation Prompt: Testing & Training Suite + Documentation Management + Remaining Fixes

You are building the testing and training suite AND a documentation management system for the claudetools Claude Code plugin. Read this entire prompt before starting any work. Your reference document is `.docs/claudetools-v3-testing-training-suite.md` which contains the full specification, code examples, and architecture.

**Important context:** The hooks.json file now includes WorktreeCreate as a confirmed lifecycle event (session-index.sh fires on worktree creation). All reference documents are in `.docs/` not in the repo root.

---

## Phase 0: Fix Remaining Bugs (Do This First)

Before building anything new, fix these 3 issues that have been flagged in three consecutive audits and are still unfixed:

### Fix A: failure-pattern-detector.sh line 12

**Problem:** Uses `PPID` for failure log filename. PPID is unreliable across hook invocations - it changes if Claude Code spawns hooks through different process trees, causing failure counts to reset or bleed across sessions.

**Fix:** Replace line 12:
```bash
# OLD
FAILURE_LOG="/tmp/claude-failures-${PPID}.jsonl"

# NEW
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FAILURE_LOG="/tmp/claude-failures-${SESSION_ID:-$$}.jsonl"
```

Move the SESSION_ID extraction to before line 12 (after INPUT is read on line 7).

### Fix B: enforce-team-usage.sh line 55

**Problem:** Uses `python3` to read settings.json. Every other script in the repo uses `jq`. This adds an unnecessary dependency and is inconsistent.

**Fix:** Replace line 55:
```bash
# OLD
TEAMMATE_MODE=$(python3 -c "import json; print(json.load(open('$HOME/.claude/settings.json')).get('teammateMode','auto'))" 2>/dev/null || echo "auto")

# NEW
TEAMMATE_MODE=$(jq -r '.teammateMode // "auto"' "$HOME/.claude/settings.json" 2>/dev/null || echo "auto")
```

### Fix C: enforce-team-usage.sh line 62

**Problem:** Creates `TEAM_CONFIG_CHECK` variable that's identical to `TEAM_CONFIG` defined on line 30.

**Fix:** Replace line 62:
```bash
# OLD
TEAM_CONFIG_CHECK="$HOME/.claude/teams/${TEAM_NAME}/config.json"
if [ -f "$TEAM_CONFIG_CHECK" ]; then
  MEMBER_COUNT=$(jq '.members | length' "$TEAM_CONFIG_CHECK" 2>/dev/null || echo "0")

# NEW (reuse existing TEAM_CONFIG variable)
if [ -f "$TEAM_CONFIG" ]; then
  MEMBER_COUNT=$(jq '.members | length' "$TEAM_CONFIG" 2>/dev/null || echo "0")
```

---

## Phase 1: Documentation Management System

This is a new major feature. Claude Code and Anthropic models create .md files prolifically - research notes, analysis docs, audit reports, plans, READMEs, changelogs, and more. Without management, these accumulate as stale, duplicated, disorganised clutter. The documentation management system enforces clean, versioned, well-structured docs with automatic indexing and lifecycle management.

### 1.1 The Standard Documentation Folder Structure

All documentation created by Claude within a project MUST follow this structure. This applies to any project using the plugin, not just claudetools itself.

```
docs/
  index.md                          # Auto-generated master index
  adr/                              # Architecture Decision Records
    index.md
    001-initial-architecture.md
    002-database-choice.md
  guides/                           # How-to guides (Diataxis: how-to)
    index.md
    getting-started.md
    deployment.md
  reference/                        # Technical reference (Diataxis: reference)
    index.md
    api.md
    configuration.md
  research/                         # Research notes, analysis, investigations
    index.md
    2026-03-15-competitor-analysis.md
    2026-03-15-performance-audit.md
  plans/                            # Implementation plans, RFCs, proposals
    index.md
    001-feature-x-plan.md
  reports/                          # Audit reports, session reports, reviews
    index.md
    2026-03-15-security-audit.md
  archive/                          # Superseded/deprecated docs (auto-moved)
    index.md
CHANGELOG.md                        # Project-level changelog (keep-a-changelog format)
```

The structure uses the Diataxis framework (tutorials, how-to, reference, explanation) combined with practical categories (research, plans, reports, ADRs). Date-prefixed filenames for time-sensitive docs. Numbered prefixes for sequential docs (ADRs, plans). kebab-case everywhere.

### 1.2 Mandatory Front Matter

Every .md file created by Claude MUST include YAML front matter:

```yaml
---
title: "Document Title"
created: "2026-03-15"
modified: "2026-03-15"
version: "1.0.0"
status: "active"           # draft | active | review | deprecated | archived
category: "research"       # adr | guide | reference | research | plan | report
tags: ["security", "audit"]
supersedes: ""             # Path to doc this replaces (if any)
superseded_by: ""          # Path to doc that replaces this (if any)
author: "claude"           # or user name
---
```

Status lifecycle: `draft` -> `active` -> `review` -> `deprecated` -> `archived`

When a doc is superseded:
1. Set `status: deprecated` and `superseded_by: path/to/new-doc.md` on the old doc
2. Set `supersedes: path/to/old-doc.md` on the new doc
3. Move the old doc to `docs/archive/` automatically

### 1.3 Index Files

Every directory under `docs/` MUST have an `index.md` that is auto-generated. Format:

```markdown
---
title: "Research Index"
created: "2026-03-15"
modified: "2026-03-15"
version: "auto"
status: "active"
category: "index"
auto_generated: true
---

# Research

| Document | Status | Created | Modified | Version |
|----------|--------|---------|----------|---------|
| [Competitor Analysis](2026-03-15-competitor-analysis.md) | active | 2026-03-15 | 2026-03-15 | 1.0.0 |
| [Performance Audit](2026-03-15-performance-audit.md) | active | 2026-03-15 | 2026-03-15 | 1.0.0 |

*Auto-generated by claudetools doc-manager. Do not edit manually.*
```

The master `docs/index.md` lists all categories with counts and links to sub-indexes.

### 1.4 File Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| ADR | `NNN-kebab-title.md` | `001-database-choice.md` |
| Guide | `kebab-title.md` | `getting-started.md` |
| Reference | `kebab-title.md` | `api-endpoints.md` |
| Research | `YYYY-MM-DD-kebab-title.md` | `2026-03-15-competitor-analysis.md` |
| Plan | `NNN-kebab-title.md` | `001-feature-x-plan.md` |
| Report | `YYYY-MM-DD-kebab-title.md` | `2026-03-15-security-audit.md` |

Rules enforced by the hook:
- All lowercase
- kebab-case only (no underscores, no spaces, no camelCase)
- No generic names: `notes.md`, `temp.md`, `test.md`, `draft.md`, `output.md`, `result.md`, `doc.md`
- Maximum filename length: 80 characters
- Must end in `.md`

### 1.5 Hook: doc-manager.sh (PostToolUse on Edit|Write)

This hook fires after every Edit or Write and manages documentation lifecycle.

**File:** `scripts/doc-manager.sh`

**Behaviour:**

```bash
#!/usr/bin/env bash
# doc-manager.sh - PostToolUse hook for Edit|Write
# Enforces documentation standards, auto-updates indexes, manages lifecycle.
# Only acts on .md files. Exits 0 for non-md files immediately.

set -euo pipefail
source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

# Only process .md files
[[ "$FILE_PATH" != *.md ]] && exit 0

# Skip files outside the project (temp files, system files)
[[ "$FILE_PATH" == /tmp/* ]] && exit 0
[[ "$FILE_PATH" == /dev/* ]] && exit 0

FILENAME=$(basename "$FILE_PATH")
DIRNAME=$(dirname "$FILE_PATH")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# --- 1. Enforce file naming conventions ---
# Check kebab-case (allow date prefixes and number prefixes)
if [[ "$FILENAME" =~ [A-Z] ]]; then
  echo "Documentation naming violation: '$FILENAME' contains uppercase. Use kebab-case (all lowercase with hyphens)." >&2
  exit 2
fi

if [[ "$FILENAME" =~ [_\ ] ]]; then
  echo "Documentation naming violation: '$FILENAME' contains underscores or spaces. Use kebab-case (hyphens only)." >&2
  exit 2
fi

# Block generic names
GENERIC_NAMES="notes.md temp.md test.md draft.md output.md result.md doc.md document.md untitled.md new.md"
for generic in $GENERIC_NAMES; do
  if [ "$FILENAME" = "$generic" ]; then
    echo "Documentation naming violation: '$FILENAME' is too generic. Use a descriptive name like 'auth-module-notes.md' or '2026-03-15-performance-analysis.md'." >&2
    exit 2
  fi
done

# --- 2. Enforce front matter on new files ---
if [ "$TOOL_NAME" = "Write" ]; then
  # Check if the file has front matter (starts with ---)
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' | head -5)
  if [[ "$CONTENT" != "---"* ]]; then
    echo "Documentation standard violation: New .md file '$FILENAME' missing YAML front matter." >&2
    echo "All documentation must start with front matter including: title, created, modified, version, status, category." >&2
    echo "Example:" >&2
    echo "---" >&2
    echo "title: \"Your Title\"" >&2
    echo "created: \"$(date +%Y-%m-%d)\"" >&2
    echo "modified: \"$(date +%Y-%m-%d)\"" >&2
    echo "version: \"1.0.0\"" >&2
    echo "status: \"draft\"" >&2
    echo "category: \"research\"" >&2
    echo "---" >&2
    exit 2
  fi
fi

# --- 3. Auto-update modified date on edits ---
if [ "$TOOL_NAME" = "Edit" ] && [ -f "$FILE_PATH" ]; then
  TODAY=$(date +%Y-%m-%d)
  # Check if file has front matter with modified field
  if head -20 "$FILE_PATH" | grep -q '^modified:'; then
    CURRENT_MODIFIED=$(head -20 "$FILE_PATH" | grep '^modified:' | sed 's/modified: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ "$CURRENT_MODIFIED" != "$TODAY" ]; then
      # Update the modified date in-place
      sed -i "s/^modified:.*/modified: \"$TODAY\"/" "$FILE_PATH" 2>/dev/null || true
      hook_log "updated modified date to $TODAY for $FILENAME"
    fi
  fi
fi

# --- 4. Detect potential doc to archive ---
# If a file sets superseded_by in its front matter, flag for archival
if [ -f "$FILE_PATH" ] && head -20 "$FILE_PATH" | grep -q 'superseded_by:.*[a-z]'; then
  SUPERSEDED_BY=$(head -20 "$FILE_PATH" | grep 'superseded_by:' | sed 's/superseded_by: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
  if [ -n "$SUPERSEDED_BY" ]; then
    echo "Note: '$FILENAME' has been marked as superseded by '$SUPERSEDED_BY'. Consider moving it to docs/archive/." >&2
    hook_log "doc superseded: $FILENAME -> $SUPERSEDED_BY"
  fi
fi

# --- 5. Detect docs created outside docs/ structure ---
# Only warn, don't block - some .md files are legitimate outside docs/ (README.md, CHANGELOG.md, CLAUDE.md, etc.)
ALLOWED_ROOT_MDS="readme.md changelog.md contributing.md license.md claude.md code_of_conduct.md security.md"
LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')

IS_ROOT_ALLOWED=false
for allowed in $ALLOWED_ROOT_MDS; do
  [ "$LOWER_FILENAME" = "$allowed" ] && IS_ROOT_ALLOWED=true
done

# Check if file is inside a docs/ directory (at any level)
if [[ "$FILE_PATH" != */docs/* ]] && [[ "$FILE_PATH" != */.docs/* ]] && ! $IS_ROOT_ALLOWED; then
  # It's a .md file outside docs/ and not a standard root file
  echo '{"systemMessage":"You created a .md file outside the docs/ directory. Documentation should be placed in the appropriate docs/ subdirectory (docs/research/, docs/plans/, docs/reports/, etc.) with proper front matter. Standard root files like README.md, CHANGELOG.md, CLAUDE.md are exempt."}' || true
  hook_log "doc outside docs/: $FILE_PATH"
fi

exit 0
```

### 1.6 Hook: doc-index-generator.sh (SessionEnd - async)

Regenerates index.md files for all docs/ subdirectories at session end.

**File:** `scripts/doc-index-generator.sh`

```bash
#!/usr/bin/env bash
# doc-index-generator.sh - SessionEnd hook (async)
# Regenerates index.md files in all docs/ subdirectories.
# Scans front matter for title, status, created, modified, version.

set -euo pipefail
source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)

# Find the project root (walk up from cwd looking for .git or .claude)
PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

DOCS_DIR="$PROJECT_ROOT/docs"

# Only run if docs/ directory exists
[ -d "$DOCS_DIR" ] || exit 0

hook_log "regenerating doc indexes in $DOCS_DIR"

# Function: extract front matter field
extract_field() {
  local file="$1" field="$2"
  head -30 "$file" 2>/dev/null | sed -n '/^---$/,/^---$/p' | grep "^${field}:" | sed "s/${field}: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/" | head -1
}

# Function: generate index for a directory
generate_index() {
  local dir="$1"
  local dir_name=$(basename "$dir")
  local title=$(echo "$dir_name" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')  # kebab to Title Case
  local index_file="$dir/index.md"
  local today=$(date +%Y-%m-%d)

  # Collect all .md files except index.md
  local md_files=()
  while IFS= read -r f; do
    [ "$(basename "$f")" != "index.md" ] && md_files+=("$f")
  done < <(find "$dir" -maxdepth 1 -name '*.md' -type f | sort)

  [ ${#md_files[@]} -eq 0 ] && return

  # Build index content
  cat > "$index_file" <<HEADER
---
title: "$title Index"
created: "$today"
modified: "$today"
version: "auto"
status: "active"
category: "index"
auto_generated: true
---

# $title

| Document | Status | Created | Modified | Version |
|----------|--------|---------|----------|---------|
HEADER

  for f in "${md_files[@]}"; do
    local fname=$(basename "$f")
    local ftitle=$(extract_field "$f" "title")
    [ -z "$ftitle" ] && ftitle="$fname"
    local fstatus=$(extract_field "$f" "status")
    [ -z "$fstatus" ] && fstatus="-"
    local fcreated=$(extract_field "$f" "created")
    [ -z "$fcreated" ] && fcreated="-"
    local fmodified=$(extract_field "$f" "modified")
    [ -z "$fmodified" ] && fmodified="-"
    local fversion=$(extract_field "$f" "version")
    [ -z "$fversion" ] && fversion="-"

    echo "| [$ftitle]($fname) | $fstatus | $fcreated | $fmodified | $fversion |" >> "$index_file"
  done

  echo "" >> "$index_file"
  echo "*Auto-generated by claudetools doc-manager. Do not edit manually.*" >> "$index_file"

  hook_log "generated index for $dir_name (${#md_files[@]} docs)"
}

# Generate indexes for each subdirectory
for subdir in "$DOCS_DIR"/*/; do
  [ -d "$subdir" ] && generate_index "$subdir"
done

# Generate master index
MASTER_INDEX="$DOCS_DIR/index.md"
TODAY=$(date +%Y-%m-%d)

cat > "$MASTER_INDEX" <<HEADER
---
title: "Documentation Index"
created: "$TODAY"
modified: "$TODAY"
version: "auto"
status: "active"
category: "index"
auto_generated: true
---

# Documentation

HEADER

for subdir in "$DOCS_DIR"/*/; do
  [ -d "$subdir" ] || continue
  local_name=$(basename "$subdir")
  local_title=$(echo "$local_name" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')
  doc_count=$(find "$subdir" -maxdepth 1 -name '*.md' ! -name 'index.md' -type f | wc -l | tr -d ' ')
  echo "- [$local_title]($local_name/index.md) ($doc_count documents)" >> "$MASTER_INDEX"
done

echo "" >> "$MASTER_INDEX"
echo "*Auto-generated by claudetools doc-manager. Do not edit manually.*" >> "$MASTER_INDEX"

hook_log "master index regenerated"
exit 0
```

### 1.7 Hook: doc-stale-detector.sh (SessionStart)

At session start, scan docs/ for stale documents and warn Claude.

**File:** `scripts/doc-stale-detector.sh`

```bash
#!/usr/bin/env bash
# doc-stale-detector.sh - SessionStart hook
# Scans docs/ for stale, deprecated, or problematic documents.
# Outputs warnings to stdout (injected into Claude's context).

set -euo pipefail
source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)

PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

DOCS_DIR="$PROJECT_ROOT/docs"
[ -d "$DOCS_DIR" ] || exit 0

STALE_DAYS=30
TODAY_EPOCH=$(date +%s)
ISSUES=""

# Function: extract front matter field
extract_field() {
  local file="$1" field="$2"
  head -30 "$file" 2>/dev/null | sed -n '/^---$/,/^---$/p' | grep "^${field}:" | sed "s/${field}: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/" | head -1
}

# Scan all .md files (skip index.md files)
while IFS= read -r md_file; do
  [ "$(basename "$md_file")" = "index.md" ] && continue

  fname=$(basename "$md_file")
  rel_path="${md_file#$PROJECT_ROOT/}"

  # Check for missing front matter
  if ! head -1 "$md_file" | grep -q '^---$'; then
    ISSUES="${ISSUES}\n  - $rel_path: missing front matter"
    continue
  fi

  # Check status
  status=$(extract_field "$md_file" "status")
  if [ "$status" = "deprecated" ]; then
    superseded_by=$(extract_field "$md_file" "superseded_by")
    ISSUES="${ISSUES}\n  - $rel_path: DEPRECATED (superseded by $superseded_by) - move to archive/"
    continue
  fi

  # Check staleness (modified date > 30 days ago)
  modified=$(extract_field "$md_file" "modified")
  if [ -n "$modified" ]; then
    mod_epoch=$(date -d "$modified" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$modified" +%s 2>/dev/null || echo "0")
    if [ "$mod_epoch" -gt 0 ]; then
      days_old=$(( (TODAY_EPOCH - mod_epoch) / 86400 ))
      if [ "$days_old" -gt "$STALE_DAYS" ]; then
        ISSUES="${ISSUES}\n  - $rel_path: stale (last modified ${days_old} days ago, status: ${status:-unknown})"
      fi
    fi
  fi

  # Check for draft status older than 7 days
  if [ "$status" = "draft" ]; then
    created=$(extract_field "$md_file" "created")
    if [ -n "$created" ]; then
      created_epoch=$(date -d "$created" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$created" +%s 2>/dev/null || echo "0")
      if [ "$created_epoch" -gt 0 ]; then
        draft_days=$(( (TODAY_EPOCH - created_epoch) / 86400 ))
        if [ "$draft_days" -gt 7 ]; then
          ISSUES="${ISSUES}\n  - $rel_path: draft for ${draft_days} days - finalise or remove"
        fi
      fi
    fi
  fi

done < <(find "$DOCS_DIR" -name '*.md' -type f)

if [ -n "$ISSUES" ]; then
  echo "[Documentation Health]"
  echo -e "$ISSUES"
  echo "  Run /docs-audit to review and clean up documentation."
  hook_log "doc health issues found"
fi

exit 0
```

### 1.8 Add Hooks to hooks.json

Add the following entries to hooks.json:

**PostToolUse - add doc-manager.sh to the Edit|Write matcher:**

In the existing `PostToolUse` -> `Edit|Write` hooks array, add doc-manager.sh:
```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/doc-manager.sh"
}
```

**SessionEnd - add doc-index-generator.sh (async):**

Add a new entry in the SessionEnd array:
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/doc-index-generator.sh",
      "async": true,
      "timeout": 15
    }
  ]
}
```

**SessionStart - add doc-stale-detector.sh:**

Add a new entry in the SessionStart array:
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/doc-stale-detector.sh",
      "timeout": 5
    }
  ]
}
```

### 1.9 Create /docs-manager Skill

**Directory:** `skills/docs-manager/`

**skills/docs-manager/SKILL.md:**

```yaml
---
name: docs-manager
description: "Manage project documentation. Use when the user says: organise docs, clean up documentation, audit docs, create docs structure, docs health, stale docs, archive old docs, update indexes, /docs-audit, /docs-init."
argument-hint: "[init|audit|archive|reindex]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
context: fork
agent: general-purpose
metadata:
  author: Owen Innes
  version: 1.0.0
  category: documentation
  tags: [docs, documentation, management, indexing, audit]
---

# Documentation Manager

Manage, audit, and organise project documentation following claudetools standards.

## Commands

### init - Initialise docs structure

Create the standard docs/ folder structure for this project:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-init.sh
```

Creates: docs/{adr,guides,reference,research,plans,reports,archive}/ with index.md in each.

### audit - Audit documentation health

Scan all docs for issues: missing front matter, stale content, deprecated docs not archived, naming violations, orphaned files.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-audit.sh
```

### archive - Archive deprecated/superseded docs

Move all docs with `status: deprecated` to docs/archive/, updating indexes.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh
```

### reindex - Regenerate all index files

Force regeneration of all index.md files in docs/ subdirectories.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/docs-reindex.sh
```

## Documentation Standards

All .md files managed by this system must:

1. Have YAML front matter with: title, created, modified, version, status, category
2. Use kebab-case filenames (all lowercase, hyphens only)
3. Use date-prefixed names for research/reports (YYYY-MM-DD-title.md)
4. Use number-prefixed names for ADRs/plans (NNN-title.md)
5. Live inside the docs/ directory (except README.md, CHANGELOG.md, CLAUDE.md)
6. Have a descriptive name (not notes.md, temp.md, draft.md)

## Status Lifecycle

draft -> active -> review -> deprecated -> archived

When a doc is superseded:
1. Set status: deprecated and superseded_by on the old doc
2. Set supersedes on the new doc
3. Run /docs-manager archive to move to docs/archive/
```

### 1.10 Skill Scripts

**skills/docs-manager/scripts/docs-init.sh:**

```bash
#!/usr/bin/env bash
# Initialise the standard docs/ folder structure
set -euo pipefail

PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

DOCS_DIR="$PROJECT_ROOT/docs"
TODAY=$(date +%Y-%m-%d)

CATEGORIES="adr guides reference research plans reports archive"

for cat in $CATEGORIES; do
  mkdir -p "$DOCS_DIR/$cat"
  TITLE=$(echo "$cat" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')

  cat > "$DOCS_DIR/$cat/index.md" <<EOF
---
title: "$TITLE Index"
created: "$TODAY"
modified: "$TODAY"
version: "auto"
status: "active"
category: "index"
auto_generated: true
---

# $TITLE

No documents yet.

*Auto-generated by claudetools doc-manager. Do not edit manually.*
EOF
done

# Master index
cat > "$DOCS_DIR/index.md" <<EOF
---
title: "Documentation Index"
created: "$TODAY"
modified: "$TODAY"
version: "auto"
status: "active"
category: "index"
auto_generated: true
---

# Documentation

$(for cat in $CATEGORIES; do
  TITLE=$(echo "$cat" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')
  echo "- [$TITLE]($cat/index.md) (0 documents)"
done)

*Auto-generated by claudetools doc-manager. Do not edit manually.*
EOF

echo "Documentation structure initialised at $DOCS_DIR/"
echo "Categories: $CATEGORIES"
```

**skills/docs-manager/scripts/docs-audit.sh:**

```bash
#!/usr/bin/env bash
# Audit documentation health - comprehensive scan
set -euo pipefail

PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

DOCS_DIR="$PROJECT_ROOT/docs"
TODAY_EPOCH=$(date +%s)

echo "=== Documentation Audit ==="
echo "Scanning: $DOCS_DIR"
echo ""

ERRORS=0 WARNINGS=0

extract_field() {
  head -30 "$1" 2>/dev/null | sed -n '/^---$/,/^---$/p' | grep "^${2}:" | sed "s/${2}: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/" | head -1
}

# 1. Check docs/ structure exists
if [ ! -d "$DOCS_DIR" ]; then
  echo "ERROR: No docs/ directory found. Run /docs-manager init to create it."
  exit 1
fi

# 2. Scan all .md files
while IFS= read -r f; do
  fname=$(basename "$f")
  rel="${f#$PROJECT_ROOT/}"

  [ "$fname" = "index.md" ] && continue

  # Check front matter exists
  if ! head -1 "$f" | grep -q '^---$'; then
    echo "ERROR: $rel - missing front matter"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check required fields
  for field in title created modified version status category; do
    val=$(extract_field "$f" "$field")
    if [ -z "$val" ]; then
      echo "ERROR: $rel - missing required field: $field"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check naming
  if [[ "$fname" =~ [A-Z] ]]; then
    echo "ERROR: $rel - filename contains uppercase (use kebab-case)"
    ERRORS=$((ERRORS + 1))
  fi

  # Check staleness
  modified=$(extract_field "$f" "modified")
  status=$(extract_field "$f" "status")
  if [ -n "$modified" ]; then
    mod_epoch=$(date -d "$modified" +%s 2>/dev/null || echo "0")
    if [ "$mod_epoch" -gt 0 ]; then
      days=$((  (TODAY_EPOCH - mod_epoch) / 86400 ))
      if [ "$days" -gt 90 ]; then
        echo "WARNING: $rel - very stale (${days} days since last modified)"
        WARNINGS=$((WARNINGS + 1))
      elif [ "$days" -gt 30 ]; then
        echo "WARNING: $rel - stale (${days} days since last modified)"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi

  # Check deprecated not archived
  if [ "$status" = "deprecated" ] && [[ "$f" != */archive/* ]]; then
    echo "WARNING: $rel - status is deprecated but not in archive/"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Check drafts older than 7 days
  if [ "$status" = "draft" ]; then
    created=$(extract_field "$f" "created")
    if [ -n "$created" ]; then
      cr_epoch=$(date -d "$created" +%s 2>/dev/null || echo "0")
      if [ "$cr_epoch" -gt 0 ] && [ $(( (TODAY_EPOCH - cr_epoch) / 86400 )) -gt 7 ]; then
        echo "WARNING: $rel - draft for $(( (TODAY_EPOCH - cr_epoch) / 86400 )) days"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi

done < <(find "$DOCS_DIR" -name '*.md' -type f 2>/dev/null)

# 3. Check for .md files outside docs/
ORPHANS=0
while IFS= read -r f; do
  fname=$(basename "$f")
  lower=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
  # Skip standard root files
  case "$lower" in
    readme.md|changelog.md|contributing.md|license.md|claude.md|code_of_conduct.md|security.md) continue ;;
  esac
  # Skip files in special directories
  [[ "$f" == */.git/* ]] && continue
  [[ "$f" == */node_modules/* ]] && continue
  [[ "$f" == */docs/* ]] && continue
  [[ "$f" == */.docs/* ]] && continue
  [[ "$f" == */skills/* ]] && continue
  [[ "$f" == */agents/* ]] && continue

  echo "WARNING: Orphaned doc outside docs/: ${f#$PROJECT_ROOT/}"
  ORPHANS=$((ORPHANS + 1))
  WARNINGS=$((WARNINGS + 1))
done < <(find "$PROJECT_ROOT" -name '*.md' -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

echo ""
echo "=== Audit Results ==="
echo "Errors: $ERRORS | Warnings: $WARNINGS | Orphaned docs: $ORPHANS"

if [ "$ERRORS" -gt 0 ]; then
  echo "Fix errors before proceeding."
  exit 1
fi

echo "Documentation health: OK"
```

**skills/docs-manager/scripts/docs-archive.sh:**

```bash
#!/usr/bin/env bash
# Move deprecated docs to archive/
set -euo pipefail

PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

DOCS_DIR="$PROJECT_ROOT/docs"
ARCHIVE_DIR="$DOCS_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

extract_field() {
  head -30 "$1" 2>/dev/null | sed -n '/^---$/,/^---$/p' | grep "^${2}:" | sed "s/${2}: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/" | head -1
}

MOVED=0

while IFS= read -r f; do
  [ "$(basename "$f")" = "index.md" ] && continue
  [[ "$f" == */archive/* ]] && continue

  status=$(extract_field "$f" "status")
  if [ "$status" = "deprecated" ] || [ "$status" = "archived" ]; then
    fname=$(basename "$f")

    # Update status to archived
    sed -i 's/^status:.*/status: "archived"/' "$f" 2>/dev/null || true

    mv "$f" "$ARCHIVE_DIR/$fname"
    echo "Archived: $(basename "$(dirname "$f")")/$fname -> archive/$fname"
    MOVED=$((MOVED + 1))
  fi
done < <(find "$DOCS_DIR" -name '*.md' -type f)

echo "Archived $MOVED documents."
```

**skills/docs-manager/scripts/docs-reindex.sh:**

```bash
#!/usr/bin/env bash
# Force regeneration of all index files
# Reuses the doc-index-generator.sh logic
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"

echo '{}' | bash "$PLUGIN_ROOT/scripts/doc-index-generator.sh"
echo "All indexes regenerated."
```

---

## Phase 2: Install BATS and Create Test Infrastructure

### 2.1 Install BATS

```bash
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
cd /tmp/bats-core && sudo ./install.sh /usr/local
```

If sudo is not available, install to a local prefix and add to PATH.

### 2.2 Create Directory Structure

```
tests/
  bats/
    test-helper.bash
    doc-manager.bats              # NEW: tests for doc management hooks
  fixtures/
    dangerous-commands.txt
    safe-commands.txt
    boundary-commands.txt
    hook-inputs/
    stub-samples/
    doc-samples/                  # NEW: sample .md files for doc hook testing
      valid-doc.md                # Has correct front matter
      no-frontmatter.md           # Missing front matter
      uppercase-Name.md           # Bad naming
      notes.md                    # Generic name
      stale-doc.md                # Modified 60 days ago
      deprecated-doc.md           # Status: deprecated
  scaffolds/
    node-project/
    python-project/
    rust-project/
    go-project/
    general-project/
  training/
    scenarios/
      code/
      non-code/
      edge-cases/
    runner.sh
    scorer.sh
    report.sh
  run-all.sh
```

### 2.3 Create test-helper.bash

Copy the `test-helper.bash` from `.docs/claudetools-v3-testing-training-suite.md`. This provides:
- `setup_test_db` / `teardown_test_db` for temporary metrics.db
- `run_hook` function that pipes JSON to hooks and captures exit code + stdout + stderr
- `assert_blocked`, `assert_allowed`, `assert_exit` helpers
- `seed_sessions`, `seed_failures` for populating test data

---

## Phase 3: Write BATS Unit Tests

Write one `.bats` file per hook script. The spec document contains full examples for `block-dangerous-bash.bats` and `failure-pattern-detector.bats`. Follow this pattern for all hooks:

### Priority order (test the most critical hooks first):

1. `block-dangerous-bash.bats` - 20+ test cases (dangerous, safe, boundary)
2. `auto-approve-safe.bats` - 30+ test cases covering all 8 language ecosystems
3. `guard-sensitive-files.bats` - Test read-allowed vs write-blocked for .env, .ssh, credentials
4. `failure-pattern-detector.bats` - Test pattern counting, adaptive thresholds, warn vs block
5. `capture-outcome.bats` + `capture-failure.bats` - Verify SQLite writes (success=1 vs success=0)
6. `edit-frequency-guard.bats` - Test flock, adaptive threshold reads, warning messages
7. `verify-no-stubs.bats` - Test per-language stub patterns, .pyi skip, except/else filter
8. `block-stub-writes.bats` - Test that .sh files are no longer skipped
9. `inject-session-context.bats` - Test memory injection, churn warnings, first-run silence
10. `dynamic-rules.bats` - Test all 8 project types, threshold injection, failure injection
11. `enforce-team-usage.bats` - Test Explore/Plan bypass, team validation, block message
12. `archive-restore-compact.bats` - Test PreCompact creates file, PostCompact restores state
13. `config-audit-trail.bats` - Test jq-based JSON construction
14. `doc-manager.bats` - Test naming enforcement, front matter validation, modified date updates, generic name blocking, outside-docs warnings

### Test case guidelines:

- Every test must use `run_hook` from test-helper.bash
- Every test must assert an exit code
- Tests for blocking hooks must verify the JSON output structure
- Include at least 3 happy-path and 3 failure-path cases per hook
- Include edge cases: empty input, malformed JSON, missing fields
- For hooks that read metrics.db, test both with and without the DB existing

### doc-manager.bats specific tests:

```bash
@test "allows .md file with valid front matter and kebab-case name" {
  # Write a valid doc, verify exit 0
}

@test "blocks .md file with uppercase in filename" {
  # Write to MyDoc.md, verify exit 2
}

@test "blocks .md file with generic name" {
  # Write to notes.md, verify exit 2
}

@test "blocks .md file without front matter" {
  # Write content without --- header, verify exit 2
}

@test "allows non-.md files without any checks" {
  # Write to file.ts, verify exit 0 (immediate skip)
}

@test "warns when .md file created outside docs/" {
  # Write to /project/random-doc.md, verify systemMessage warning
}

@test "allows README.md at project root" {
  # Write to /project/README.md, verify exit 0 (no warning)
}

@test "auto-updates modified date on edit" {
  # Edit a doc with old modified date, verify it changes to today
}
```

---

## Phase 4: Create Safety Command Corpus

(Unchanged from previous version - see `.docs/claudetools-v3-testing-training-suite.md` for full corpus specification)

### fixtures/dangerous-commands.txt - 100+ dangerous commands
### fixtures/safe-commands.txt - 500+ safe commands across all ecosystems
### fixtures/boundary-commands.txt - 200+ boundary cases
### test-safety-corpus.sh - Computes precision/recall (targets: FP < 2%, FN = 0%)

---

## Phase 5: Integration Tests

### test-self-learning-pipeline.sh

Copy from the spec document. Tests the full capture -> aggregate -> inject -> tune cycle.

### test-compaction-survival.sh

Test PreCompact -> PostCompact with real git state.

### test-doc-management.sh (NEW)

Integration test for the documentation management system:

```bash
#!/usr/bin/env bash
# Integration test for documentation management
set -euo pipefail

WORK_DIR=$(mktemp -d /tmp/claudetools-doctest-XXXXXX)
cd "$WORK_DIR"
git init

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# 1. Test docs-init
echo "Testing docs-init..."
bash "$PLUGIN_ROOT/skills/docs-manager/scripts/docs-init.sh"
[ -f "docs/index.md" ] && echo "PASS: master index created" || echo "FAIL: no master index"
[ -f "docs/research/index.md" ] && echo "PASS: research index created" || echo "FAIL: no research index"
[ -f "docs/adr/index.md" ] && echo "PASS: adr index created" || echo "FAIL: no adr index"

# 2. Create a valid doc
cat > "docs/research/2026-03-15-test-analysis.md" <<'EOF'
---
title: "Test Analysis"
created: "2026-03-15"
modified: "2026-03-15"
version: "1.0.0"
status: "active"
category: "research"
tags: ["test"]
---

# Test Analysis

This is a test document.
EOF

# 3. Test docs-reindex
echo "Testing docs-reindex..."
bash "$PLUGIN_ROOT/skills/docs-manager/scripts/docs-reindex.sh"
if grep -q "Test Analysis" docs/research/index.md; then
  echo "PASS: reindex includes new doc"
else
  echo "FAIL: reindex missing new doc"
fi

# 4. Test docs-audit
echo "Testing docs-audit..."
audit_output=$(bash "$PLUGIN_ROOT/skills/docs-manager/scripts/docs-audit.sh" 2>&1)
if echo "$audit_output" | grep -q "Documentation health: OK"; then
  echo "PASS: audit passes on valid docs"
else
  echo "FAIL: audit reported issues on valid docs"
  echo "$audit_output"
fi

# 5. Create a deprecated doc and test archiving
cat > "docs/research/2026-01-01-old-analysis.md" <<'EOF'
---
title: "Old Analysis"
created: "2026-01-01"
modified: "2026-01-01"
version: "1.0.0"
status: "deprecated"
category: "research"
superseded_by: "2026-03-15-test-analysis.md"
---

# Old Analysis

This has been superseded.
EOF

echo "Testing docs-archive..."
bash "$PLUGIN_ROOT/skills/docs-manager/scripts/docs-archive.sh"
if [ -f "docs/archive/2026-01-01-old-analysis.md" ]; then
  echo "PASS: deprecated doc archived"
else
  echo "FAIL: deprecated doc not moved to archive"
fi

# Cleanup
rm -rf "$WORK_DIR"
echo ""
echo "=== Doc Management Integration Test Complete ==="
```

---

## Phase 6: Scaffold Projects

(Unchanged from previous version)

---

## Phase 7: Training Scenarios

Create 20 scenario JSON files. Include all original scenarios plus:

### Additional doc-related scenarios in edge-cases/:

21. **Doc sprawl scenario** - Prompt asks Claude to "create notes for each finding" (should be directed to docs/research/ with proper front matter)
22. **Doc cleanup scenario** - Project has 10 stale docs in wrong locations (doc-stale-detector should flag, agent should use /docs-manager audit to clean up)

---

## Phase 8: Training Runner, Scorer, and Report

(Unchanged from previous version - copy from spec document)

---

## Phase 9: Training via Native /loop

**IMPORTANT: Do NOT create a custom /loop skill.** `/loop` is a native Claude Code built-in skill that schedules recurring prompts using cron under the hood (`CronCreate`/`CronList`/`CronDelete` tools). It is session-scoped - tasks fire between turns while Claude is idle, and vanish when the session exits.

### How /loop works

```text
/loop [interval] [task description]
```

- Interval accepts natural language: `5m`, `30m`, `2h`, `1d` (minimum granularity: 1 minute)
- Default interval: 10 minutes if omitted
- Tasks fire at low priority between your turns
- 50-task limit per session, auto-expires after 3 days
- You can loop over other skills: `/loop 20m /code-review`

### What to build instead: Training Prompt Files

Create prompt files that an agent (or user) passes to `/loop` or runs directly via `claude -p`. These are plain text files containing the instructions for each training workflow.

**Directory:** `tests/training/prompts/`

#### tests/training/prompts/train-code-scenario.md

```markdown
You are running a claudetools training iteration. Follow these steps exactly:

1. Pick ONE random scenario from tests/training/scenarios/code/ that has not been run in the last training batch (check tests/training/results/ for recent runs).

2. Set up the scenario:
   - Copy the matching scaffold from tests/training/scaffolds/ to a temp directory
   - Run the scenario's setup script if one exists
   - Note the scenario ID and expected outcomes

3. Execute the scenario prompt against the scaffold project. Work naturally as you would on any task. The plugin hooks will fire and capture metrics automatically.

4. After completing the task (or hitting a block), run:
   ```bash
   bash tests/training/scorer.sh tests/training/results/latest/
   ```

5. Record the result:
   - Append a line to tests/training/results/training-log.jsonl with: scenario_id, model, score, tool_calls, failures, duration, timestamp
   - If score < 60, note which hooks fired unexpectedly or failed to fire

6. If this is the 5th+ iteration in this batch, run threshold analysis:
   ```bash
   bash skills/tune-thresholds/scripts/analyse-metrics.sh
   ```
   Review the output and apply any recommended threshold adjustments if they improve the score trend.

7. Report: "Training iteration complete. Scenario: [id], Score: [score]/100, Failures: [count]"
```

#### tests/training/prompts/train-noncode-scenario.md

Same structure but picks from `tests/training/scenarios/non-code/`.

#### tests/training/prompts/train-edge-case.md

Same structure but picks from `tests/training/scenarios/edge-cases/`.

#### tests/training/prompts/run-deterministic-tests.md

```markdown
Run the claudetools deterministic test suite. Follow these steps:

1. Run BATS unit tests:
   ```bash
   bash tests/run-all.sh
   ```

2. Run the self-learning pipeline integration test:
   ```bash
   bash tests/test-self-learning-pipeline.sh
   ```

3. Run the safety corpus accuracy test:
   ```bash
   bash tests/test-safety-corpus.sh
   ```

4. Run the documentation management integration test:
   ```bash
   bash tests/test-doc-management.sh
   ```

5. Report results: total pass/fail counts, any failures with details, safety corpus FP/FN rates.

6. If any tests fail, diagnose the root cause and fix it. Then re-run the failing tests to confirm the fix.
```

#### tests/training/prompts/model-comparison.md

```markdown
Run a full model comparison benchmark for claudetools.

1. For each model (haiku, sonnet, opus):
   ```bash
   bash tests/training/runner.sh [model] all 25
   ```

2. Score all results:
   ```bash
   bash tests/training/scorer.sh tests/training/results/latest/
   ```

3. Generate comparison report:
   ```bash
   bash tests/training/report.sh
   ```

4. Output the comparison table with: avg score, tool calls, failures, duration, estimated cost per model.

5. Recommend the best model for production use based on score-to-cost ratio.
```

### How the user runs training

**One-off training run:**
```text
claude -p "$(cat tests/training/prompts/train-code-scenario.md)"
```

**Looped training (runs every 30 minutes during session):**
```text
/loop 30m Run one training iteration from tests/training/prompts/train-code-scenario.md
```

**Deterministic tests on a schedule:**
```text
/loop 2h Run the deterministic test suite from tests/training/prompts/run-deterministic-tests.md
```

**For persistent scheduling (Claude Desktop only):**
Use the Schedule sidebar to create a daily task that runs the deterministic tests and a weekly task for a full model comparison.

### Create a /train Skill (NOT /loop)

Instead of overriding the native /loop, create a `/train` skill that wraps the training workflow with a nice interface.

**Directory:** `skills/train/`

**skills/train/SKILL.md:**

```yaml
---
name: train
description: "Run claudetools training and testing workflows. Use when the user says: train weights, run training, test hooks, run tests, benchmark models, training loop, run deterministic tests, safety corpus, model comparison."
argument-hint: "[test|code|noncode|edge|compare|all]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
context: fork
agent: general-purpose
metadata:
  author: Owen Innes
  version: 1.0.0
  category: meta
  tags: [testing, training, self-learning, benchmarking, evals]
---

# Training & Testing Suite

Run claudetools test and training workflows to validate hooks, train self-learning weights, and benchmark across models.

## Commands

### /train test
Run the deterministic test suite (BATS + integration tests). Zero API tokens.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/run-all.sh && \
bash ${CLAUDE_PLUGIN_ROOT}/tests/test-self-learning-pipeline.sh && \
bash ${CLAUDE_PLUGIN_ROOT}/tests/test-safety-corpus.sh && \
bash ${CLAUDE_PLUGIN_ROOT}/tests/test-doc-management.sh
```

### /train code
Run one code training scenario. Uses tokens.
Follow the instructions in: `${CLAUDE_PLUGIN_ROOT}/tests/training/prompts/train-code-scenario.md`

### /train noncode
Run one non-code training scenario. Uses tokens.
Follow the instructions in: `${CLAUDE_PLUGIN_ROOT}/tests/training/prompts/train-noncode-scenario.md`

### /train edge
Run one edge case training scenario. Uses tokens.
Follow the instructions in: `${CLAUDE_PLUGIN_ROOT}/tests/training/prompts/train-edge-case.md`

### /train compare
Run full model comparison benchmark across haiku, sonnet, and opus.
Follow the instructions in: `${CLAUDE_PLUGIN_ROOT}/tests/training/prompts/model-comparison.md`

### /train all
Run deterministic tests first, then one of each scenario type (code, noncode, edge).

## Continuous Training via /loop

To run training continuously during a session, use Claude Code's native /loop:
```
/loop 30m /train code
/loop 1h /train noncode
/loop 2h /train test
```

For persistent daily training, use Claude Desktop's Schedule feature to create a recurring task.

## Workflow

1. Always start with `/train test` to verify hooks work deterministically
2. Run `/train code` with haiku first (cheapest) to establish baseline
3. Run `/train code` again to accumulate metrics data
4. After 5+ iterations, run `/tune-thresholds` to adjust adaptive weights
5. Re-run `/train test` to verify threshold changes don't break safety
6. Run `/train compare` for full model benchmark when ready
```

---

## Phase 10: run-all.sh Master Script

Create `tests/run-all.sh` that:
1. Checks BATS is installed (installs if not)
2. Runs all `.bats` files in `tests/bats/` (including doc-manager.bats)
3. Outputs TAP results
4. Records pass/fail count to metrics.db
5. Exits with failure count as exit code

---

## Phase 11: Verify Everything

After building all of the above:

1. Run `bash tests/run-all.sh` and fix any failing tests
2. Run `bash tests/test-self-learning-pipeline.sh` and verify all PASS
3. Run `bash tests/test-safety-corpus.sh` and verify FP < 2%, FN = 0%
4. Run `bash tests/test-doc-management.sh` and verify all PASS
5. Verify the /train skill directory has correct structure (skills/train/SKILL.md)
6. Verify the /docs-manager skill directory has correct structure
7. Verify all scaffold projects have the minimum required files
8. Verify hooks.json includes doc-manager.sh, doc-index-generator.sh, and doc-stale-detector.sh
9. Verify training prompt files exist in tests/training/prompts/
10. Test that `/train test` works end-to-end

---

## Key Principles

- **Deterministic first, agent-driven second.** Layer 1 and 2 should pass with 0 API calls before any training runs.
- **Every hook gets tested.** No hook should be untested. If a hook is too complex to unit test (e.g., prompt hooks), test the command hooks around it.
- **Safety is non-negotiable.** The FN rate for dangerous commands must be exactly 0%. Any dangerous command that gets through is a critical bug.
- **Non-code is first-class.** At least 5 of the 20 training scenarios are non-code tasks. The plugin is domain-agnostic.
- **Documentation is managed, not sprawled.** Every .md file gets front matter, lives in docs/, has a category, and gets indexed. Stale docs are flagged. Deprecated docs are archived. No exceptions except standard root files (README, CHANGELOG, CLAUDE.md).
- **Use native /loop, don't replace it.** Training runs are triggered via Claude Code's built-in `/loop` command or the `/train` skill. The `/train` skill is a wrapper around the training scripts. `/loop 30m /train code` chains them together for continuous autonomous training.
- **Costs matter.** Use haiku for baseline training. Only use sonnet/opus for comparison runs.
- **The self-learning pipeline is the product.** The test suite must verify that data flows correctly through: capture -> aggregate -> inject -> tune.

---

## File Count Estimate (Updated)

| Directory | Files | Lines (approx) |
|-----------|-------|-----------------|
| scripts/ (new hooks) | 3 | 400 |
| skills/docs-manager/ | 5 | 350 |
| skills/train/ | 1 | 80 |
| tests/bats/ | 15 | 1600 |
| tests/fixtures/ | 18 | 1300 |
| tests/scaffolds/ | 15 | 300 |
| tests/training/scenarios/ | 22 | 700 |
| tests/training/prompts/ | 5 | 200 |
| tests/training/ | 3 | 300 |
| tests/ | 5 | 500 |
| **Total** | **92 files** | **~5730 lines** |
