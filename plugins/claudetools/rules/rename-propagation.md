---
paths: ["**/*.md", "**/*.json", "**/*.sh", "**/*.js", "**/*.ts", "**/*.mjs", "**/*.css"]
---

# Rename Propagation Rule

When renaming ANY skill, command, agent, or directory in this plugin, ALL of the following must be updated in the SAME commit:

## Checklist (mandatory for every rename)

1. **Directory**: `plugin/skills/<name>/` or `plugin/agents/<name>.md`
2. **SKILL.md name field**: `name:` in frontmatter
3. **Agent .md name field**: `name:` in frontmatter (if agent exists)
4. **hooks.json**: any references to the old name
5. **Agent definitions**: all `plugin/agents/*.md` that reference the renamed skill
6. **Plugin README**: `plugin/README.md` — badge URLs, alt text, table text
7. **Synced copy**: `plugins/claudetools/` via rsync
8. **Docs astro config**: `docs/astro.config.mjs` sidebar entries
9. **Docs content files**: rename the .md file + update ALL references in every other .md file
10. **Public marketplace README**: push via GitHub API
11. **Public docs**: push to ClaudeTools/marketplace repo

## Verification command

After any rename, run:
```bash
grep -rn "OLD_NAME" plugin/ docs/src/ docs/astro.config.mjs | grep -v node_modules | grep -v .git
```
Result MUST be empty. If not, fix before committing.

## Current canonical skill names

| Skill | Directory | Agent |
|-------|-----------|-------|
| codebase-explorer | plugin/skills/codebase-explorer/ | plugin/agents/codebase-explorer.md |
| debugger | plugin/skills/debugger/ | plugin/agents/debugger.md |
| frontend-design | plugin/skills/frontend-design/ | — |
| plugin-improver | plugin/skills/plugin-improver/ | — |
| prompt-improver | plugin/skills/prompt-improver/ | — |
| safety-evaluator | plugin/skills/safety-evaluator/ | — |
| task-manager | plugin/skills/task-manager/ | — |
