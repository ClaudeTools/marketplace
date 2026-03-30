#!/usr/bin/env bash
# collect-metrics.sh — Field review metrics collection
# Delegates to lib/health-report.sh for shared queries
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$PLUGIN_ROOT/scripts/lib/health-report.sh"

field_review_report "${1:-30}"
