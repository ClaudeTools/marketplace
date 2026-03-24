# Manifest Upgrade Plan

> Extracted from native-alignment-gap-analysis.md — Phase 2 design document

## Version Bump Strategy

This restructure changes user-facing slash command paths (skills → commands) and removes hook-based behavioral injection. This warrants a **major version bump** via conventional commit:

```
feat!: restructure plugin to align with native .claude/ conventions
```

CI auto-version will detect `!` suffix and bump major (e.g., 3.x.x → 4.0.0).

## plugin.json Changes

No structural changes needed — plugin.json declares name, version, description, and mcpServers. The directory layout changes (commands/, reorganized skills/) are auto-discovered by Claude Code's plugin loader. Version is bumped by CI.

## marketplace.json Changes

Update description to reflect new structure:
- Mention commands/ directory for user-invoked workflows
- Update skill count (14 → 6)

## CI/CD Impact

**publish-marketplace.yml:** No changes needed — it runs rsync from plugin/ to plugins/claudetools/, which picks up the new directory structure automatically.

**auto-version.sh:** No changes needed — conventional commit `feat!:` triggers major bump.

## Upgrade Notes for Existing Users

### Breaking Changes
1. **Slash command paths change:** 8 skills that were invoked as `/claudetools:name` will now be `/project:name` commands after update
2. **Behavioral injection removed:** Some hook-injected instructions now come from rules/ files — behavior should be identical but delivery mechanism changed

### Migration Path
- Commands that were skills still work — just invoked differently
- All behavioral rules preserved in rules/ files — no loss of enforcement
- Test suite validates identical behavior post-migration

### No Action Required
- Rules, agents, and remaining skills auto-load from new locations
- hooks.json changes are transparent to users
- MCP servers (task-system, codebase-pilot) unchanged
