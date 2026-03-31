#!/usr/bin/env bash
# skill-router.sh — Tier 1 intent classification for workflow injection

classify_intent() {
  local text="${1:-}"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  case "$lower" in
    *debug*|*"fix this"*|*"fix the"*|*"why is"*failing*|*"not working"*|*broken*|*"unexpected behav"*|*error*traceback*|*stacktrace*)
      echo "debug"; return 0 ;;
  esac
  case "$lower" in
    *"where is"*|*"find where"*|*"trace the"*|*"how does"*work*|*"explore"*code*|*"show me"*|*"what calls"*)
      echo "explore"; return 0 ;;
  esac
  case "$lower" in
    *"research"*|*"look up"*doc*|*"check the"*api*|*"find doc"*|*"what api"*|*"how does"*api*)
      echo "research"; return 0 ;;
  esac
  case "$lower" in
    *"review"*code*|*"code review"*|*"audit"*code*|*"check quality"*)
      echo "review"; return 0 ;;
  esac
  case "$lower" in
    *"health"*|*"metrics"*|*"session stat"*|*"hook perform"*|*"how is the plugin"*)
      echo "health"; return 0 ;;
  esac
  case "$lower" in
    *"merge"*|*"create pr"*|*"pull request"*|*deploy*|*publish*|*release*|*"ship it"*|*"push to"*)
      echo "ship"; return 0 ;;
  esac
  case "$lower" in
    *"build feature"*|*"build a "*|*"create feature"*|*"create a new"*|*"implement feature"*|*"implement a "*|*"add feature"*|*"add a feature"*|*"new feature"*|*"write a new"*|*"refactor the"*|*"refactor this"*|*"restructure"*|*"set up"*|*"set up a "*|*"integrate with"*)
      echo "design"; return 0 ;;
  esac
  echo ""; return 0
}

format_workflow_context() {
  local cmd="${1:-}"
  case "$cmd" in
    design) cat <<'CTX'
[workflow] This task needs the design phase first. Follow this process:
1. DISCOVER: Explore codebase (codebase-pilot), check memory, research external deps
2. ARCHITECT: Present 2-3 approaches via AskUserQuestion with preview panels
3. PLAN: Write implementation plan with exact file paths and TDD steps
4. HANDOFF: Ask user "Ready to build?" → /build
Do NOT write implementation code until the plan is approved.
CTX
      ;;
    build) cat <<'CTX'
[workflow] Build phase. Execute the plan with test-driven development:
- For each task: write failing test → implement → verify → commit
- Dispatch subagents for independent tasks
- Report progress: "Task N/M complete. Tests: X/Y passing."
- After all tasks: "Ready to ship?" → /ship
CTX
      ;;
    ship) cat <<'CTX'
[workflow] Ship phase. Deliver with evidence:
1. Pre-flight: tests pass, no uncommitted changes, branch up to date
2. Code review: correctness, security, performance, maintainability
3. Deliver: create PR (gh pr create), monitor CI (gh pr checks --watch)
4. Report: "PR #N created. CI: ✓ passing."
CTX
      ;;
    debug) echo "[workflow] Debug: reproduce → observe → hypothesize → verify → fix → confirm. Evidence before fixes." ;;
    explore) echo "[workflow] Explore: use codebase-pilot (map, find-symbol, related-files) to understand the code." ;;
    research) echo "[workflow] Research: find current docs (WebSearch), verify API endpoints, check SDK versions before implementing." ;;
    review) echo "[workflow] Review: 4-pass (correctness → security → performance → maintainability)." ;;
    health) echo "[workflow] Health: run session-dashboard + field-review for combined metrics." ;;
  esac
}
