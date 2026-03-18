#!/usr/bin/env bash
# dynamic-rules.sh — InstructionsLoaded hook: inject project-type-specific rules,
# adaptive thresholds, and recent failure patterns.
# Outputs to stdout (becomes part of Claude's instructions). Always exits 0.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/detect-project.sh"

# shellcheck disable=SC2034
INPUT=$(cat)

detect_project_type
hook_log "detected project type=${PROJECT_TYPE}"

# --- 1. Project-specific build/test commands ---
case "$PROJECT_TYPE" in
  node)
    echo "Typecheck: npx tsc --noEmit | Test: npm test | Lint: npx eslint ."
    # Check for specific frameworks
    if [ -f "package.json" ]; then
      if grep -q '"next"' package.json 2>/dev/null; then
        echo "Framework: Next.js detected. Use 'next build' for full build validation."
      fi
      if grep -q '"vitest"' package.json 2>/dev/null; then
        echo "Test runner: vitest detected. Use 'npx vitest run' instead of 'npm test' if jest is not configured."
      fi
    fi
    ;;
  python)
    echo "Typecheck: pyright or mypy | Test: pytest | Lint: ruff check ."
    if [ -f "pyproject.toml" ] && grep -q 'django' pyproject.toml 2>/dev/null; then
      echo "Framework: Django detected. Use 'python manage.py test' for Django tests."
    fi
    ;;
  rust)
    echo "Typecheck: cargo check | Test: cargo test | Lint: cargo clippy"
    ;;
  go)
    echo "Typecheck: go vet ./... | Test: go test ./... | Lint: golangci-lint run"
    ;;
  java)
    if [ -f "pom.xml" ]; then
      echo "Build: mvn compile | Test: mvn test | Lint: mvn checkstyle:check"
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
      echo "Build: gradle build | Test: gradle test | Lint: gradle check"
    fi
    ;;
  dotnet)
    echo "Build: dotnet build | Test: dotnet test | Lint: dotnet format --verify-no-changes"
    ;;
  ruby)
    echo "Test: bundle exec rspec | Lint: bundle exec rubocop"
    ;;
  swift)
    echo "Build: swift build | Test: swift test"
    ;;
  *)
    # general - no specific commands
    ;;
esac

# --- 2. Inject adaptive thresholds (if metrics.db exists) ---
if command -v sqlite3 &>/dev/null; then
  source "$(dirname "$0")/lib/ensure-db.sh"
  if ensure_metrics_db 2>/dev/null; then
    THRESHOLDS=$(sqlite3 "$METRICS_DB" \
      "SELECT metric_name || '=' || CAST(current_value AS TEXT) FROM threshold_overrides;" \
      2>/dev/null || true)
    if [ -n "$THRESHOLDS" ]; then
      echo ""
      echo "[Active Thresholds]"
      echo "$THRESHOLDS" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi
fi

# --- 3. Inject recent failure patterns (last 24h, top 3) ---
if command -v sqlite3 &>/dev/null && [ -f "${METRICS_DB:-/dev/null}" ]; then
  FAILURES=$(sqlite3 "$METRICS_DB" \
    "SELECT tool_name || ' (' || COUNT(*) || ' failures)' FROM tool_outcomes
     WHERE success = 0 AND timestamp > datetime('now', '-1 day')
     GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 3;" \
    2>/dev/null || true)
  if [ -n "$FAILURES" ]; then
    echo ""
    echo "[Recent Failure Patterns - last 24h]"
    echo "$FAILURES" | while IFS= read -r line; do
      echo "  $line"
    done
    echo "  Diagnose before retrying failed approaches."
  fi
fi

# --- 4. Memory encouragement ---
echo ""
echo "Save learnings to memory/ when you discover project patterns, user preferences, or make significant decisions."

exit 0
