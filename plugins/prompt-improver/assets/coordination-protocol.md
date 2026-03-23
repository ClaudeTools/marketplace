## Multi-Agent Coordination Protocol

When multiple Claude agents work in the same repository (via worktrees or separate sessions), they coordinate through the agent-mesh CLI to avoid conflicts and share context.

### Message Types

| Type | Purpose | Example |
|------|---------|---------|
| `info` | Status updates, progress reports | "Finished migrating auth to session-based" |
| `alert` | Urgent — the recipient should act now | "Don't edit config.ts, I'm mid-migration" |
| `request` | Asking another agent for something | "Can you review my API changes before I merge?" |
| `decision` | Architectural or design choices | "Using Zod for runtime validation, not io-ts" |

Use `info` for most messages. Use `alert` only when the other agent might create a conflict if they continue without knowing. Use `decision` for choices that should persist in the shared context store (these are also stored via `context --set`).

### Lock Etiquette

1. **Lock before multi-file refactors.** If you're renaming a function across 5 files, lock the primary file so others know not to touch it.
2. **Lock scope should be narrow.** Lock specific files, not entire directories. Lock only what you're actively changing.
3. **Unlock promptly.** Release locks as soon as your changes are committed. Holding locks across idle periods blocks others.
4. **Check before locking.** Run `who --file <path>` before editing shared files. If someone else holds the lock, message them instead of waiting silently.
5. **Locks are advisory.** They don't prevent writes — they signal intent. Respect them as you would a "do not disturb" sign.

### Conflict Resolution

- **Lock holder wins.** If two agents want to edit the same file, the one who locked it first has priority. The other agent should adapt their approach or wait.
- **No lock? First commit wins.** Without locks, the agent whose changes are committed first takes precedence. The other agent rebases or adjusts.
- **Communicate, don't guess.** If you see another agent working on related files, send a message. A 10-second coordination message saves a 10-minute merge conflict.
- **Escalate to the user.** If two agents have genuinely conflicting approaches (e.g., different auth strategies), neither should proceed. Both should report the conflict and let the user decide.

### Decision Sharing

Use the shared context store (`context --set`) for decisions that affect the whole codebase:

- **Architecture choices:** "auth-strategy" = "session-based, not JWT"
- **Conventions:** "test-framework" = "vitest, not jest"
- **Blockers:** "ci-status" = "broken — PR #42 failed, do not merge"
- **Coordination:** "migration-owner" = "agent-refactor — do not touch schema.prisma"

Before starting work that depends on a shared decision, check the context store:
```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --get "auth-strategy"
```

### Practical Examples

**Starting a refactor:**
```bash
# Check who's active
node cli.js list --brief
# Lock the file you're refactoring
node cli.js lock --file src/auth/middleware.ts --id $SESSION_ID --reason "refactoring auth flow"
# Alert others
node cli.js send --to other-agent --message "Refactoring auth middleware, will take ~10 min" --type alert
# ... do the work ...
# Unlock when done
node cli.js unlock --file src/auth/middleware.ts --id $SESSION_ID
# Share the decision
node cli.js context --set "auth-refactor" "Complete — middleware now uses session store"
```

**Discovering a blocker:**
```bash
# Alert the team
node cli.js send --broadcast --message "CI is broken — test-db container is down" --type alert
# Record it in shared context
node cli.js context --set "ci-status" "broken — test-db container down"
```
