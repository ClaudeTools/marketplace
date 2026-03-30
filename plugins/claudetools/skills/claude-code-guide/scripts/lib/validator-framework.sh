#!/usr/bin/env bash
# validator-framework.sh — Shared pass/fail/warn output and summary logic for validate-*.sh scripts
# Source this file at the top of each validator script:
#   source "$(dirname "$0")/lib/validator-framework.sh"

_VF_PASS=0
_VF_FAIL=0
_VF_WARN=0

vf_pass() {
  echo "  PASS: $1"
  _VF_PASS=$((_VF_PASS + 1))
}

vf_fail() {
  echo "  FAIL: $1"
  _VF_FAIL=$((_VF_FAIL + 1))
}

vf_warn() {
  echo "  WARN: $1"
  _VF_WARN=$((_VF_WARN + 1))
}

vf_section() {
  echo ""
  echo "--- $1 ---"
}

vf_summary() {
  echo ""
  echo "=== RESULT ==="
  if [ "$_VF_FAIL" -eq 0 ] && [ "$_VF_WARN" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
  elif [ "$_VF_FAIL" -eq 0 ]; then
    echo "PASSED with $_VF_WARN warning(s)"
  else
    echo "FAILED: $_VF_FAIL error(s), $_VF_WARN warning(s)"
  fi
}

vf_exit() {
  exit "$_VF_FAIL"
}
