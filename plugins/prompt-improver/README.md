# claudetools

Self-learning guardrail system for Claude Code. Hooks intercept tool calls, evaluate risk with adaptive thresholds, and improve over time from session metrics.

## Installation

```bash
claude plugin install claudetools owenob1/claude-tools
```

## What's Included

- **42 hooks** -- PreToolUse/PostToolUse guardrails covering file ops, git, bash, destructive actions
- **8 skills** -- /train, /session-dashboard, /tune-thresholds, /debug-investigator, /code-review, /prompt-improver, /docs-manager, /train
- **9 agents** -- architect, test-writer, code-reviewer, researcher, and specialized task agents
- **Self-learning layer** -- per-model adaptive weights trained from session data, cross-model evaluation pipeline

## Quick Start

After installation, claudetools activates automatically. Hooks run on every tool call. To check system health:

```
/session-dashboard
```

To tune guardrail sensitivity after a session:

```
/tune-thresholds
```

To run training scenarios:

```
/train
```

## Configuration

Thresholds and model-specific multipliers live in `data/db-thresholds.json`. Run `/tune-thresholds` to adjust based on observed metrics.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
