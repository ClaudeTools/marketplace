#!/usr/bin/env bash
# Validator: session-stop-gate — multi-tier quality check at session end
# Sourced by session-stop-dispatcher.sh after hook_init().
# Globals used: INPUT, CWD, MODEL_FAMILY, METRICS_DB
#
# Tier 1: Deterministic (return 2 = hard block)
#   - Main branch, uncommitted changes, sensitive files, stub patterns
# Tier 2: Semantic grep (return 1 = warning)
#   - Weasel phrases, scope check
#
# Tier 3 (AI audit) has been extracted to ai-session-audit.sh (async hook).

validate_session_stop_gate() {
  local cwd="${CWD:-.}"

  # Prevent infinite loops
  local stop_active
  stop_active=$(hook_get_field '.stop_hook_active' 2>/dev/null || true)
  if [ "$stop_active" = "true" ]; then
    return 0
  fi

  # ═══════════════════════════════════════════════════════════════
  # TIER 1: Deterministic checks (return 2 on failure)
  # ═══════════════════════════════════════════════════════════════

  source "$SCRIPT_DIR/lib/git-state.sh"

  local is_git=0
  git_is_repo "$cwd" && is_git=1

  # --- 1a. Main branch check ---
  # Only block if on main AND there are uncommitted changes — the risk is unreviewed
  # direct commits, not simply being on main after a clean merge.
  if [ "$is_git" -eq 1 ]; then
    local current_branch
    current_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
      local dirty
      dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c '^[^?]' || true)
      if [ "${dirty:-0}" -gt 0 ]; then
        echo "On $current_branch with uncommitted changes — create a feature branch to keep code review in the loop." >&2
        record_hook_outcome "session-stop-gate" "Stop" "warn" "" "" "" "$MODEL_FAMILY"
        return 1
      fi
    fi
  fi

  # --- 1b. Uncommitted changes ---
  if [ "$is_git" -eq 1 ]; then
    local changed_files
    changed_files=$(git_changed_files "$cwd")

    if [ -n "$changed_files" ]; then
      local file_count
      file_count=$(echo "$changed_files" | wc -l | tr -d ' ')

      echo "$file_count uncommitted file(s). Uncommitted work is lost when the session ends — commit or stash before stopping." >&2
      record_hook_outcome "session-stop-gate" "Stop" "warn" "" "" "" "$MODEL_FAMILY"
    fi
  fi

  # No git repo and no changes — skip remaining file checks
  if [ "$is_git" -eq 0 ]; then
    record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
    return 0
  fi

  # --- 1c. Sensitive files staged ---
  local sensitive_staged
  sensitive_staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | grep -iE '\.(env|key|pem|p12|pfx|keystore)$|credentials|secrets' || true)
  if [ -n "$sensitive_staged" ]; then
    echo "Sensitive files staged: $(echo "$sensitive_staged" | tr '\n' ', ') — unstage these before committing to avoid leaking credentials." >&2
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
    return 2
  fi

  # --- 1d. Stub/TODO patterns in recently changed files ---
  local recent_code_files
  recent_code_files=$(git -C "$cwd" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|py|go|rs|rb|java)$' | grep -vE '\.test\.|\.spec\.|__tests__|__mocks__' || true)

  local stub_count=0
  if [ -n "$recent_code_files" ]; then
    local file full_path count
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      full_path="$file"
      [ "${file:0:1}" != "/" ] && full_path="$cwd/$file"
      [ -f "$full_path" ] || continue

      count=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme|placeholder)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|HACK:' "$full_path" 2>/dev/null || true)
      count=${count:-0}
      if [ "$count" -gt 0 ]; then
        stub_count=$((stub_count + count))
      fi
    done <<< "$recent_code_files"
  fi

  if [ "$stub_count" -gt 0 ]; then
    echo "$stub_count stub/TODO patterns in recent changes — implement or remove them before stopping." >&2
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" "" "$MODEL_FAMILY"
    return 2
  fi

  # ═══════════════════════════════════════════════════════════════
  # TIER 2: Semantic checks (return 1 = warning)
  # ═══════════════════════════════════════════════════════════════

  local warnings=0

  # --- 2a. Weasel phrases ---
  local weasel_hits
  weasel_hits=$(echo "$INPUT" | grep -oiE 'should work|looks correct|appears to|I believe this fixes|it should be fine|probably works|seems to work|I think this is right|this might fix|likely resolves' 2>/dev/null || true)
  if [ -n "$weasel_hits" ]; then
    local weasel_count
    weasel_count=$(echo "$weasel_hits" | wc -l | tr -d ' ')
    echo "$weasel_count uncertain phrase(s) detected — verify claims with tests, not confidence" >&2
    warnings=1
  fi

  # --- 2b. Scope check ---
  local recent_changed
  recent_changed=$(git -C "$cwd" diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ' || true)
  recent_changed=${recent_changed:-0}
  [[ "$recent_changed" =~ ^[0-9]+$ ]] || recent_changed=0
  local large_change
  large_change=$(get_threshold "large_change_threshold" 2>/dev/null || echo "15")
  large_change=${large_change%.*}
  if [ "$recent_changed" -gt "$large_change" ]; then
    echo "Large change set: $recent_changed files in last commit — verify scope matches the task" >&2
    warnings=1
  fi

  if [ "$warnings" -gt 0 ]; then
    record_hook_outcome "session-stop-gate" "Stop" "warn" "" "" "" "$MODEL_FAMILY"
    return 1
  fi

  # All clear
  record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" "" "$MODEL_FAMILY"
  return 0
}
