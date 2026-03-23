---
name: field-review
description: Field review of the claudetools plugin itself (NOT code review). Reports on hooks, validators, skills performance — false positives, bugs, gaps, praise. Use when the user says claudetools review, plugin feedback, field report, audit the plugin, rate claudetools.
argument-hint: [--days N] [--submit]
allowed-tools: Read, Bash, Grep, Glob, Write
metadata:
  author: Owen Innes
  version: 1.0.0
  category: meta
  tags: [feedback, plugin-review, telemetry, field-report]
---

# claudetools Plugin Field Review

Generate a structured review of how the claudetools plugin is performing in the current project. This creates a rich local report AND optionally submits a sanitized summary to cross-install telemetry for improvement prioritization.

## Purpose

You are reviewing the claudetools plugin as a practitioner who uses it daily. Your observations are valuable — you see things that metrics alone cannot capture: false positives that erode trust, missing features that would save time, workflow gaps that force manual workarounds, and things that genuinely help.

This is YOUR review. The structure below is a scaffold to ensure completeness, not a straitjacket. If you have observations that don't fit neatly into a section, include them. If a section isn't relevant to your experience, say so briefly and move on. Depth matters more than coverage — a single well-documented false positive with evidence is worth more than a list of vague complaints.

## Phase 1: Data Collection

Run the metrics collection script to get quantitative context:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/collect-metrics.sh ${DAYS:-30}
```

Read the output carefully. This is your evidence base — hook outcomes, failure rates, threshold status, and a changelog showing what recently changed in the plugin. Note anything surprising: hooks with high block rates, tools that fail often, thresholds that have been modified, or new features you haven't tried yet.

If the script reports no metrics.db or no sqlite3, that's fine — proceed with qualitative observations from your experience. The changelog section shows recent version changes so you can comment on new features, regressions, or improvements you've noticed.

## Phase 2: Reflection

Now reflect on your experience with the plugin. Consider each component category, but don't force observations where you have none.

**Hooks & Validators** — The guardrail system
- Which hooks helped you catch real mistakes?
- Which hooks got in your way with false positives? What specifically triggered them incorrectly?
- Were any hooks missing — situations where a guardrail would have prevented a mistake?
- Do the warning/error messages actually help you fix the issue, or are they cryptic?

**Skills** — The high-level workflows
- Which skills did you use? Were they effective?
- Did any skill's workflow not match your actual task? (e.g., a skill designed for building that you needed for maintenance)
- What skill would have saved you time but doesn't exist?

**codebase-pilot** — Code navigation
- Did the index work? Was it useful?
- What queries did you wish existed?
- How does it compare to just using grep/glob directly?

**Memory System** — Cross-session context
- Did memories persist useful context?
- Did stale memories cause confusion?
- Was the auto-extraction helpful or noisy?

**Telemetry & Metrics** — Self-awareness
- Is the data being collected useful?
- Are adaptive thresholds tuning in the right direction?

**Overall Developer Experience**
- Does the plugin feel like a help or a hindrance?
- What's the single biggest improvement opportunity?
- What should absolutely NOT change?

## Phase 3: Report

Generate a markdown report. Save it to:
```
.claude/plugins/feedback/claudetools-review-{date}.md
```

Use this structure as a starting point, but adapt it to what you actually have to say:

```markdown
# claudetools Field Review

**Date:** {YYYY-MM-DD}
**Project type:** {brief description — e.g., "Next.js SaaS", "Python CLI", "Rust library"}
**Plugin version:** {from collect-metrics output}
**Review context:** {what you were doing when this review was triggered}

## Overall Assessment

{Your honest overall take. Grade if it helps (A-F), but the narrative matters more.
What's the headline? Is the plugin pulling its weight? Is it getting in the way?
Be specific — "it's good" is useless; "the pre-edit gate caught 3 real blind-edit
mistakes this week but false-flagged on every utils/ edit" is gold.}

## What Works Well

{List the components, hooks, skills, or behaviors that genuinely help.
For each, explain WHY it works — what would be worse without it.}

## Issues Found

{This is the meat of the review. Organize however makes sense for your findings.
Possible categories: false positives, bugs, missing features, workflow gaps,
documentation issues, performance problems, confusing messages.

For each issue:
- What component is affected
- What happened (specific, with evidence if possible)
- What should have happened
- Suggested severity (critical/high/medium/low)
- Suggested fix if you have one}

## Component Notes

{Optional per-component assessments. A table works well here but isn't required.
Only include components you have meaningful observations about.}

## Recommendations

{Prioritized list of suggested improvements.
P0 = trust-breaking issues that should be fixed immediately
P1 = meaningful improvements that affect daily workflow
P2 = nice-to-haves and polish}

## Session Metrics

{Include relevant numbers from the collect-metrics output.
Don't just dump the raw output — highlight what's interesting.}
```

## Phase 4: Submission Summary

After saving the full report, generate a sanitized JSON summary for cross-install telemetry. This summary must contain NO file paths, NO code snippets, NO project names — only component names, categories, and generic descriptions.

Save the JSON to:
```
.claude/plugins/feedback/claudetools-review-{date}.json
```

The JSON structure:
```json
{
  "ts": "{ISO 8601 timestamp}",
  "install_id": "{from collect-metrics or read from plugin/data/.install-id}",
  "plugin_version": "{version}",
  "project_type": "{generic category — e.g., nextjs-saas, python-cli, rust-library}",
  "project_size": "{small|medium|large}",
  "overall_grade": "{A+ through F, or null if you declined to grade}",
  "model_family": "{opus|sonnet|haiku}",
  "os": "{linux|darwin}",
  "review_type": "manual",
  "report_summary": {
    "headline": "{one-sentence summary}",
    "top_strength": "{best thing about the plugin}",
    "top_weakness": "{biggest improvement opportunity}"
  },
  "narrative": "{The WHY behind your findings — reasoning chains, interconnected observations, structural insights about the plugin architecture, workflow gaps that span multiple components. This is where you explain things that don't fit in individual items. Up to 5000 chars. NO project-specific paths or code.}",
  "self_critique": "{Honest assessment of YOUR process during this review — what you skipped, what you couldn't verify, assumptions you made, areas where your analysis may be weak. Up to 2000 chars.}",
  "component_grades": [
    {
      "component": "{hook/skill/validator/tool name}",
      "grade": "{A+ through F}",
      "notes": "{brief justification — max 500 chars}"
    }
  ],
  "items": [
    {
      "category": "{false_positive|bug|missing_feature|workflow_gap|praise|suggestion}",
      "component": "{hook/skill/validator name}",
      "severity": "{critical|high|medium|low}",
      "title": "{concise description — max 200 chars}",
      "description": "{detail — max 1000 chars, NO project-specific info}",
      "related_items": ["{indices of other items this connects to, e.g. [0, 3]}"]
    }
  ]
}
```

**Key differences from the local markdown report:**
- `narrative` captures the reasoning and interconnections that individual items can't express — the "why" behind findings, how issues relate to each other, structural observations about skill architecture
- `self_critique` preserves honest process gaps — what you skipped, what you couldn't verify, where your analysis is uncertain
- `component_grades` provides the dense grade-per-component view that individual items lose
- `related_items` on each item captures interconnections (e.g., broken codebase-pilot index → grep instead → no CSS awareness → manual pattern counting)
- `description` limit is 1000 chars (not 500) — enough for actionable detail

## Phase 5: Optional Submission

If the user passed `--submit` or confirms when asked, submit the JSON:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/submit-feedback.sh .claude/plugins/feedback/claudetools-review-{date}.json
```

If the user didn't pass `--submit`, ask them:
> "I've saved the full review and a sanitized JSON summary. Would you like to submit the summary to claudetools telemetry? This helps prioritize plugin improvements across all installs. The submission contains no file paths, code, or project-identifying information — only component names, grades, and generic issue descriptions."

Only submit after explicit user confirmation.

## Edge Cases

- **No metrics data**: Proceed with qualitative review only. Note the data gap in the report.
- **Fresh install**: Focus on first impressions — onboarding experience, initial friction points.
- **Agent hasn't used the plugin much**: Rely primarily on metrics data. Be honest about limited personal observations.
- **Multiple sessions**: Draw on accumulated experience across sessions if you have context.

## Notes

- Be honest. A review that's all praise is as useless as one that's all complaints.
- Be specific. "Hook X is annoying" tells us nothing. "Hook X fires on every utils/ edit because it pattern-matches on directory depth" is actionable.
- Be constructive. For every issue, suggest what "good" would look like.
- The full markdown report stays local — be as detailed and project-specific as you want.
- The JSON summary goes remote — keep it generic and sanitized.
