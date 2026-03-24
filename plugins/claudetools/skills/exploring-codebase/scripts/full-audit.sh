#!/usr/bin/env bash
# full-audit.sh — Run all codebase-pilot analysis commands in one pass
# Usage: full-audit.sh [project-root]
set -uo pipefail

PROJECT="${1:-$(pwd)}"
CLI="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/codebase-pilot/dist/cli.js"
SCRIPTS="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/skills/exploring-codebase/scripts"

echo "================================================================"
echo "  FULL CODEBASE AUDIT"
echo "  $(date '+%Y-%m-%d %H:%M') | $(basename "$PROJECT")"
echo "================================================================"
echo ""

# 1. Health check
echo "──── DOCTOR ────"
node "$CLI" doctor 2>&1
echo ""

# 2. Project map
echo "──── PROJECT MAP ────"
node "$CLI" map "$PROJECT" 2>&1 | head -30
echo ""

# 3. Context budget (most important files)
echo "──── CONTEXT BUDGET (top 10 most-imported) ────"
node "$CLI" context-budget 2>&1 | head -12
echo ""

# 4. API surface
echo "──── API SURFACE ────"
node "$CLI" api-surface 2>&1 | head -20
echo "..."
echo ""

# 5. Dead code
echo "──── DEAD CODE ────"
node "$CLI" dead-code 2>&1 | head -20
echo ""

# 6. Circular dependencies
echo "──── CIRCULAR DEPENDENCIES ────"
node "$CLI" circular-deps 2>&1
echo ""

# 7. Security scan
echo "──── SECURITY SCAN ────"
bash "$SCRIPTS/security-scan.sh" "$PROJECT" 2>&1 | head -40
echo ""

# 8. Complexity report
echo "──── COMPLEXITY (functions > 30 lines) ────"
bash "$SCRIPTS/complexity-report.sh" --threshold 30 "$PROJECT" 2>&1 | head -20
echo ""

echo "================================================================"
echo "  AUDIT COMPLETE"
echo "================================================================"
