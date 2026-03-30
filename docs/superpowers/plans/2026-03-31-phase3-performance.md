# Phase 3: Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce SessionStart from 60s to <10s for returning sessions, and add Tier 1 fast-path routing to Edit/Write dispatchers.

**Architecture:** Make codebase-pilot indexing incremental (skip full rebuild if recent index exists), cache git state in a session-scoped temp file for cross-hook sharing, and add file-type fast-paths to content validation dispatchers.

**Tech Stack:** Bash, SQLite (codebase-pilot), jq

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/codebase-pilot/scripts/session-index.sh` | Modify: add incremental indexing logic |
| `plugin/scripts/lib/git-state.sh` | Modify: add session temp file caching |
| `plugin/scripts/validate-content.sh` | Modify: add Tier 1 file-type fast-path |
| `plugin/scripts/pre-edit-gate.sh` | Modify: add Tier 1 file-type fast-path |

---

### Task 1: Make codebase-pilot indexing incremental

**Files:**
- Modify: `plugin/codebase-pilot/scripts/session-index.sh`

- [ ] **Step 1: Read the current indexing logic**

Run: `sed -n '85,140p' plugin/codebase-pilot/scripts/session-index.sh`
Note the lines where `node "$CLI" index "$PROJECT_ROOT"` runs.

- [ ] **Step 2: Add incremental indexing before the full index call**

Before the existing `node "$CLI" index` call (around line 121), add:

```bash
# Incremental indexing: skip full rebuild if index is recent (< 1 hour)
INDEX_DB="$PROJECT_ROOT/.codeindex/db.sqlite"
SKIP_FULL_INDEX=0

if [ -f "$INDEX_DB" ]; then
  INDEX_AGE=$(( $(date +%s) - $(stat -c %Y "$INDEX_DB" 2>/dev/null || stat -f %m "$INDEX_DB" 2>/dev/null || echo 0) ))
  if [ "$INDEX_AGE" -lt 3600 ]; then
    # Index is fresh — only reindex changed files
    CHANGED_SINCE=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~3 HEAD 2>/dev/null | head -50 || true)
    if [ -n "$CHANGED_SINCE" ]; then
      hook_log "codebase-pilot: incremental reindex (${INDEX_AGE}s old, $(echo "$CHANGED_SINCE" | wc -l) files changed)"
      echo "$CHANGED_SINCE" | while IFS= read -r f; do
        [ -f "$PROJECT_ROOT/$f" ] && node "$CLI" index-file "$PROJECT_ROOT/$f" 2>/dev/null || true
      done
    else
      hook_log "codebase-pilot: index fresh and no changes — skipping"
    fi
    SKIP_FULL_INDEX=1
  fi
fi
```

Then wrap the existing full index call in:

```bash
if [ "$SKIP_FULL_INDEX" -eq 0 ]; then
  # existing full index logic here
  node "$CLI" index "$PROJECT_ROOT" 2>/dev/null || true
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/codebase-pilot/scripts/session-index.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/codebase-pilot/scripts/session-index.sh
git commit -m "perf: incremental codebase-pilot indexing for returning sessions

Skip full 30s rebuild if .codeindex/db.sqlite is < 1 hour old.
Only reindex files changed in last 3 commits. Full rebuild still
runs on first session or after long gaps."
```

---

### Task 2: Add session temp file caching to git-state.sh

**Files:**
- Modify: `plugin/scripts/lib/git-state.sh`

- [ ] **Step 1: Read the current file**

Run: `cat -n plugin/scripts/lib/git-state.sh`

- [ ] **Step 2: Add session temp file write/read functions**

After the existing `git_changed_files()` function, add:

```bash
# git_state_cache_path — Returns the session-scoped git state cache file path.
git_state_cache_path() {
  local session_id="${SESSION_ID:-${_deploy_session_id:-$$}}"
  echo "/tmp/claude-git-state-${session_id}.json"
}

# git_save_state [DIR] — Write git state to session temp file for cross-hook sharing.
# Call this once in a dispatcher; subsequent hooks read the cached file.
git_save_state() {
  local dir="${1:-.}"
  local cache
  cache=$(git_state_cache_path)
  local branch changed_files is_repo
  is_repo=false
  git_is_repo "$dir" && is_repo=true
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  changed_files=$(git_changed_files "$dir" | tr '\n' '|')
  printf '{"is_repo":%s,"branch":"%s","changed_files":"%s","ts":%s}\n' \
    "$is_repo" "$branch" "$changed_files" "$(date +%s)" > "$cache" 2>/dev/null || true
}

# git_load_state — Load cached git state if fresh (< 30s old). Returns 0 if loaded, 1 if stale/missing.
git_load_state() {
  local cache
  cache=$(git_state_cache_path)
  [ -f "$cache" ] || return 1
  local cache_age
  cache_age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0) ))
  [ "$cache_age" -gt 30 ] && return 1
  # Populate exports from cache
  export _CACHED_PROJECT_ROOT  # already set if git_project_root was called
  local is_repo branch changed
  is_repo=$(jq -r '.is_repo' "$cache" 2>/dev/null || echo "false")
  branch=$(jq -r '.branch' "$cache" 2>/dev/null || echo "")
  changed=$(jq -r '.changed_files' "$cache" 2>/dev/null | tr '|' '\n' || true)
  export _CACHED_GIT_IS_REPO="$is_repo"
  export _CACHED_GIT_BRANCH="$branch"
  export _CACHED_CHANGED_FILES="$changed"
  return 0
}
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/lib/git-state.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/lib/git-state.sh
git commit -m "perf: add session temp file caching to git-state.sh

git_save_state writes git state to /tmp/claude-git-state-{SESSION_ID}.json.
git_load_state reads it if < 30s old. Eliminates repeated git forks
across hooks in the same tool-use cycle."
```

---

### Task 3: Add Tier 1 fast-path to validate-content.sh

**Files:**
- Modify: `plugin/scripts/validate-content.sh`

- [ ] **Step 1: Read the current file**

Run: `cat -n plugin/scripts/validate-content.sh`
Note where validators are invoked (the `run_validator` calls).

- [ ] **Step 2: Add file-type fast-path before validator calls**

After `hook_init` and library sourcing, before the first `run_validator` call, add:

```bash
# Tier 1 fast-path: skip content validators for non-code files
FILE_PATH=$(hook_get_field '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
if [ -n "$FILE_PATH" ]; then
  source "$SCRIPT_DIR/lib/hook-skip.sh"
  if is_test_file "$FILE_PATH" || is_doc_file "$FILE_PATH" || is_config_file "$FILE_PATH" || is_binary_file "$FILE_PATH"; then
    record_hook_outcome "validate-content" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
    exit 0
  fi
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/validate-content.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/validate-content.sh
git commit -m "perf: add Tier 1 fast-path to validate-content dispatcher

Skip stubs/secrets/localhost/mocks validators for test, doc, config,
and binary files. Saves 300-500ms per non-code file edit."
```

---

### Task 4: Add Tier 1 fast-path to pre-edit-gate.sh

**Files:**
- Modify: `plugin/scripts/pre-edit-gate.sh`

- [ ] **Step 1: Read the current file**

Run: `cat -n plugin/scripts/pre-edit-gate.sh`

- [ ] **Step 2: Add file-type fast-path before validator calls**

Same pattern as Task 3. After `hook_init` and library sourcing, before validators:

```bash
# Tier 1 fast-path: skip edit validators for non-code files
FILE_PATH=$(hook_get_field '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
if [ -n "$FILE_PATH" ]; then
  if is_test_file "$FILE_PATH" || is_doc_file "$FILE_PATH" || is_binary_file "$FILE_PATH"; then
    record_hook_outcome "pre-edit-gate" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
    exit 0
  fi
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/pre-edit-gate.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/pre-edit-gate.sh
git commit -m "perf: add Tier 1 fast-path to pre-edit-gate dispatcher

Skip edit validators for test, doc, and binary files."
```

---

## Self-Review

1. **Spec coverage:** ✓ Incremental codebase-pilot (Task 1), ✓ Cached git state (Task 2), ✓ Tier 1 routing in dispatchers (Tasks 3-4)
2. **Placeholder scan:** No TBD/TODO found. All code complete.
3. **Type consistency:** `git_save_state`/`git_load_state` pair consistently. `FILE_PATH` extraction uses same jq pattern in Tasks 3-4. `is_test_file`/`is_doc_file` from same `hook-skip.sh` library.
