# Audit Mode Workflow (Maintain Mode)

When the user asks to audit, fix design issues, or improve design consistency in an existing project.

---

## Step 1: Run Diagnostics

Run all three scripts in sequence:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/extract-system.py --dir .
bash ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/validate-design.sh .
python3 ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/scripts/audit-design.py --dir .
```

## Step 2: Collate Results

Combine all outputs into a single prioritized report. Order by severity: FAIL > WARN > INFO.

## Step 3: Categorize Issues

**Auto-fixable** (safe to batch-fix):
- Hardcoded colors → replace with semantic tokens
- `space-*` classes → replace with `gap` classes
- Missing `alt` text → add descriptive alt attributes

**Manual** (requires design decisions):
- Contrast failures → needs color adjustment decisions
- Missing state handling → requires component logic
- Large components → requires architectural decisions
- Responsive issues → requires layout strategy

## Step 4: Present Report and Prioritize

Show the user: total issue count, breakdown by category, which are auto-fixable vs manual.

If there are issues across multiple categories, use AskUserQuestion with multiSelect:

- **multiSelect: true** — user picks which categories to address now
- **question**: state the total issue count and that you've categorized them
- **header**: "Fix scope"
- **Each option**: label = category name with actual count (e.g. "Hardcoded colors (12)"), description = what fixing this category involves and whether it's auto-fixable
- **Only show categories that have issues** — derive the list entirely from audit output. If 1 category has issues, skip the question and just fix it.

## Step 5: Re-audit After Fixes

Re-run the audit scripts. Audit history in `.frontend-design/audit-history.json` shows the score delta — confirm improvement (score delta must be positive or zero).
