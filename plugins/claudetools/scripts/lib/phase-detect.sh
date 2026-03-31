#!/usr/bin/env bash
# phase-detect.sh — Detect current workflow phase from session state
#
# Returns one of: design, build, review, ship, done, unknown

detect_phase() {
  local cwd="${1:-.}"

  # Not a git repo → unknown
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "unknown"; return 0; }

  local branch
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # On main/master → done or not started
  case "$branch" in
    main|master) echo "done"; return 0 ;;
  esac

  # Check for plan files
  local has_plan=0
  [ -d "$cwd/docs/plans" ] && [ -n "$(ls "$cwd/docs/plans/"*.md 2>/dev/null)" ] && has_plan=1

  # Check for commits since branch point
  local commit_count
  commit_count=$(git -C "$cwd" rev-list --count main..HEAD 2>/dev/null || git -C "$cwd" rev-list --count master..HEAD 2>/dev/null || echo "0")

  # Check for review evidence
  local has_review=0
  git -C "$cwd" log --oneline -20 2>/dev/null | grep -qi 'review\|reviewed\|code review' && has_review=1

  # Check for PR
  local has_pr=0
  command -v gh &>/dev/null && gh pr view HEAD --json state 2>/dev/null | grep -q '"state"' && has_pr=1

  # Decision tree
  if [ "$has_pr" -eq 1 ]; then
    echo "ship"
  elif [ "$has_review" -eq 1 ]; then
    echo "ship"
  elif [ "$commit_count" -gt 0 ] && [ "$has_plan" -eq 1 ]; then
    echo "review"
  elif [ "$has_plan" -eq 1 ]; then
    echo "build"
  else
    echo "design"
  fi
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
