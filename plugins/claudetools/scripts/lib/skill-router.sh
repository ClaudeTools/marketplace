#!/usr/bin/env bash
# skill-router.sh — Tier 1 keyword-based intent classification
# Maps user prompts to skill names using deterministic pattern matching.
# Returns empty string if no skill matches.

# classify_intent TEXT → echoes skill name or empty
classify_intent() {
  local text="${1:-}"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  case "$lower" in
    *debug*|*"fix this"*|*"fix the"*|*"why is"*failing*|*"not working"*|*broken*|*"unexpected behav"*|*error*)
      echo "debugger"; return 0 ;;
  esac

  case "$lower" in
    *"landing page"*|*dashboard*|*"web app"*|*"ui component"*|*"dark mode"*|*"design system"*|*redesign*|*restyle*)
      echo "frontend-design"; return 0 ;;
  esac

  case "$lower" in
    *"improve prompt"*|*"prompt engineer"*|*"structure a prompt"*|*"/prompt-improver"*)
      echo "prompt-improver"; return 0 ;;
  esac

  case "$lower" in
    *"review code"*|*"code review"*|*"review the"*|*"audit code"*|*"check quality"*)
      echo "code-review"; return 0 ;;
  esac

  case "$lower" in
    *"where is"*defined*|*"find where"*|*"trace the"*|*"how does"*work*|*"explore the"*code*)
      echo "codebase-explorer"; return 0 ;;
  esac

  case "$lower" in
    *"improve plugin"*|*"self-improve"*|*"improvement loop"*|*"/plugin-improver"*)
      echo "plugin-improver"; return 0 ;;
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
