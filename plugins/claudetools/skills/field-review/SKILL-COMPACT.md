# Field Review (Compact)

> This is the compact version. For full creative workflow, invoke with `/field-review build`

Generate a structured review of how the claudetools plugin is performing. Reports on hooks, validators, skills — false positives, bugs, gaps, praise.

## Workflow

1. **Collect metrics**: `bash ${CLAUDE_SKILL_DIR}/scripts/collect-metrics.sh ${DAYS:-30}`
2. **Reflect** on hooks (false positives, missing guardrails), skills (workflow fit), codebase-pilot (index quality), memory (stale context), and overall DX.
3. **Write report** to `.claude/plugins/feedback/claudetools-review-{date}.md`
4. **Generate JSON summary** (sanitized, no paths/code/project names) to `.claude/plugins/feedback/claudetools-review-{date}.json`
5. **Submit** (optional, only with `--submit` or explicit user confirmation): `bash ${CLAUDE_SKILL_DIR}/scripts/submit-feedback.sh <json-path>`

## Key Constraints

- Be specific with evidence — "hook X fires on every utils/ edit" not "hook X is annoying".
- JSON summary must contain NO file paths, NO code snippets, NO project names.
- Only submit after explicit user confirmation.
- Always include both positives and issues — all-praise or all-complaints reviews are useless.

## Output Structure

- Overall assessment with grade (A-F)
- What works well (with WHY)
- Issues found: component, what happened, what should have happened, severity, suggested fix
- Prioritized recommendations: P0 (trust-breaking), P1 (daily workflow), P2 (polish)

## JSON Fields

`ts`, `install_id`, `plugin_version`, `project_type`, `overall_grade`, `narrative` (up to 5000 chars), `self_critique` (up to 2000 chars), `component_grades[]`, `items[]` with `category|component|severity|title|description|related_items`.

## Arguments

| Flag | Effect |
|------|--------|
| `--days N` | Metrics lookback window (default: 30) |
| `--submit` | Auto-submit JSON to telemetry |
