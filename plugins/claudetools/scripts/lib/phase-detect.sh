#!/usr/bin/env bash
# phase-detect.sh — Detect current workflow phase from session state
#
# Returns one of: design, build, review, ship, done, unknown

detect_phase() {
  local cwd="${1:-.}"
  local session_id="${2:-${SESSION_ID:-$PPID}}"
  local cache_file="/tmp/.claude-phase-${session_id}"
  local cache_ttl=120  # seconds

  # Return cached result if fresh
  if [ -f "$cache_file" ]; then
    local file_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$file_age" -lt "$cache_ttl" ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  # Not a git repo → unknown
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "unknown" | tee "$cache_file"; return 0; }

  local branch
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # On main/master → done
  case "$branch" in
    main|master) echo "done" | tee "$cache_file"; return 0 ;;
  esac

  # Check for plan files
  local has_plan=0
  [ -d "$cwd/docs/plans" ] && [ -n "$(ls "$cwd/docs/plans/"*.md 2>/dev/null)" ] && has_plan=1

  # Check for implementation commits (files outside docs/ and .claude/)
  local impl_files
  impl_files=$(git -C "$cwd" diff --name-only main..HEAD 2>/dev/null | grep -vE '^docs/|^\\.claude/' | head -1 || true)

  # Check for review evidence (local only — no network call)
  local has_review=0
  git -C "$cwd" log --oneline -20 2>/dev/null | grep -qi 'review\|reviewed\|code review' && has_review=1

  # Check for PR — cached separately with longer TTL (network call)
  local has_pr=0
  local pr_cache="/tmp/.claude-phase-pr-${session_id}"
  if command -v gh &>/dev/null; then
    if [ ! -f "$pr_cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$pr_cache" 2>/dev/null || echo 0) )) -ge 300 ]; then
      gh pr view HEAD --json state 2>/dev/null | grep -q '"state"' && has_pr=1
      echo "$has_pr" > "$pr_cache"
    else
      has_pr=$(cat "$pr_cache" 2>/dev/null || echo 0)
    fi
  fi

  # Decision tree
  local result
  if [ "$has_pr" -eq 1 ]; then
    result="ship"
  elif [ "$has_review" -eq 1 ]; then
    result="ship"
  elif [ -n "$impl_files" ] && [ "$has_plan" -eq 1 ]; then
    result="review"
  elif [ "$has_plan" -eq 1 ]; then
    result="build"
  else
    result="design"
  fi

  echo "$result" | tee "$cache_file"
}

# format_phase_context PHASE → echoes phase-specific guidance
format_phase_context() {
  local phase="${1:-}"
  case "$phase" in
    design) echo "[phase:design] No plan exists yet. Start with /design to explore and plan." ;;
    build)  echo "[phase:build] Plan exists. Execute it with /build (test-first for each task)." ;;
    review) echo "[phase:review] Code committed. Run /review for 4-pass code quality check." ;;
    ship)   echo "[phase:ship] Review done. Run /ship to create PR, verify CI, and merge." ;;
    done)   echo "[phase:done] On main branch. Start new work on a feature branch." ;;
    *)      echo "" ;;
  esac
}
