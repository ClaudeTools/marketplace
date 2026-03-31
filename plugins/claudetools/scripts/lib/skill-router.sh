#!/usr/bin/env bash
# skill-router.sh — Tier 1 keyword-based intent classification
# Maps user prompts to skill names using deterministic pattern matching.
# Returns empty string if no skill matches.

# classify_intent TEXT → echoes skill name or empty
classify_intent() {
  local text="${1:-}"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  # Debug/fix → debugger (specific, check first)
  case "$lower" in
    *debug*|*"fix this"*|*"fix the"*|*"why is"*failing*|*"not working"*|*broken*|*"unexpected behav"*|*error*traceback*|*stacktrace*)
      echo "debugger"; return 0 ;;
  esac

  # Research → research skill (before implementation)
  case "$lower" in
    *"research"*|*"look up"*docs*|*"check the"*api*|*"find docs"*|*"what api"*|*"how does"*api*work*)
      echo "research"; return 0 ;;
  esac

  # Build/create/implement → workflow (design first, not straight to code)
  case "$lower" in
    *"build"*|*"create"*|*"implement"*|*"add feature"*|*"add a"*|*"new feature"*|*"write a"*)
      echo "workflow"; return 0 ;;
  esac

  # Refactor → workflow (design first)
  case "$lower" in
    *refactor*|*restructure*|*reorganize*|*"clean up"*)
      echo "workflow"; return 0 ;;
  esac

  # Frontend/UI → frontend-design (specific domain)
  case "$lower" in
    *"landing page"*|*dashboard*|*"web app"*|*"ui component"*|*"dark mode"*|*"design system"*|*redesign*|*restyle*)
      echo "frontend-design"; return 0 ;;
  esac

  # Review → code-review
  case "$lower" in
    *"review code"*|*"code review"*|*"review the"*|*"audit code"*|*"check quality"*)
      echo "code-review"; return 0 ;;
  esac

  # Ship/deploy → workflow conductor
  case "$lower" in
    *"merge"*|*"create pr"*|*"pull request"*|*deploy*|*publish*|*release*|*ship*)
      echo "workflow"; return 0 ;;
  esac

  # Explore → codebase-explorer
  case "$lower" in
    *"where is"*defined*|*"find where"*|*"trace the"*|*"how does"*work*|*"explore the"*code*)
      echo "codebase-explorer"; return 0 ;;
  esac

  # Prompt engineering → prompt-improver
  case "$lower" in
    *"improve prompt"*|*"prompt engineer"*|*"structure a prompt"*|*"/prompt-improver"*)
      echo "prompt-improver"; return 0 ;;
  esac

  # Plugin improvement → plugin-improver
  case "$lower" in
    *"improve plugin"*|*"self-improve"*|*"improvement loop"*|*"/plugin-improver"*)
      echo "plugin-improver"; return 0 ;;
  esac

  # Health/metrics → session-dashboard
  case "$lower" in
    *"health"*|*"metrics"*|*"session stats"*|*"hook performance"*|*"how is the plugin"*)
      echo "session-dashboard"; return 0 ;;
  esac

  echo ""
  return 0
}

# format_skill_hint SKILL_NAME → echoes a context injection string
format_skill_hint() {
  local skill="${1:-}"
  [ -z "$skill" ] && return 0
  echo "[skill-hint] The /$skill skill is relevant to this task. Invoke it before starting work."
}
