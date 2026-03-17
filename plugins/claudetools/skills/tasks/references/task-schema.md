# Task Schema Reference

Data model documentation for the task management system's persistent storage.

## tasks.json

The primary state file. Located at `.tasks/tasks.json`. Contains an array of task objects.

### Top-level structure

```json
{
  "version": 1,
  "updated_at": "2026-03-17T12:00:00.000Z",
  "session_id": "abc123",
  "tasks": [ ... ]
}
```

| Field        | Type    | Description                                      |
|-------------|---------|--------------------------------------------------|
| version     | number  | Schema version. Currently `1`.                   |
| updated_at  | string  | ISO 8601 timestamp of last write.                |
| session_id  | string  | Claude session ID that last modified the file.   |
| tasks       | array   | Array of task objects (see below).               |

### Task object

```json
{
  "id": "task-a3f8b2c1",
  "content": "Implement JWT authentication",
  "status": "in_progress",
  "priority": "high",
  "tags": ["auth", "backend"],
  "parent_id": null,
  "dependencies": [],
  "files_touched": ["src/auth/jwt.ts", "src/middleware/auth.ts"],
  "created_at": "2026-03-17T10:00:00.000Z",
  "updated_at": "2026-03-17T11:30:00.000Z",
  "completed_at": null,
  "session_id": "abc123",
  "metadata": {}
}
```

| Field          | Type         | Default    | Nullable | Set by      | Description                                                |
|---------------|-------------|------------|----------|-------------|------------------------------------------------------------|
| id            | string       | generated  | no       | hook        | Deterministic ID (see ID generation below).                |
| content       | string       | (required) | no       | hook        | Task description. Matched against TodoWrite content.       |
| status        | string       | "pending"  | no       | hook        | Current status (see valid transitions below).              |
| priority      | string       | "medium"   | yes      | MCP/skill   | One of: low, medium, high, critical.                       |
| tags          | string[]     | []         | no       | MCP/skill   | Freeform tags for grouping and filtering.                  |
| parent_id     | string       | null       | yes      | MCP/skill   | ID of parent task. Null for top-level tasks.               |
| dependencies  | string[]     | []         | no       | MCP/skill   | IDs of tasks that must complete before this one can start. |
| files_touched | string[]     | []         | no       | MCP/skill   | File paths modified while working on this task.            |
| created_at    | string       | generated  | no       | hook        | ISO 8601 timestamp of creation.                            |
| updated_at    | string       | generated  | no       | hook        | ISO 8601 timestamp of last modification.                   |
| completed_at  | string       | null       | yes      | hook        | ISO 8601 timestamp when status became "completed".         |
| session_id    | string       | from env   | no       | hook        | Session that created or last modified the task.            |
| metadata      | object       | {}         | no       | MCP/skill   | Arbitrary key-value pairs for extensibility.               |

**Field ownership:**
- The **hook** populates: `id`, `content`, `status`, `created_at`, `updated_at`, `completed_at`, `session_id`. These are derived from TodoWrite events and cannot be set manually.
- The **MCP server or skill** populates: `priority`, `tags`, `parent_id`, `dependencies`, `files_touched`, `metadata`. These are enrichment fields set via task_update or task_create.

## ID Generation

Task IDs are deterministic, derived from the task content:

1. Take the `content` string.
2. Compute SHA-256 hash.
3. Truncate to the first 8 hexadecimal characters.
4. Prefix with `task-`.

Result: `task-a3f8b2c1`

**Same content always produces the same ID.** This makes the hook idempotent — restoring a task with the same content reuses the same ID rather than creating a duplicate.

### Collision handling

If two different content strings produce the same 8-char prefix (probability ~1 in 4 billion):
1. The hook detects the collision during write.
2. It appends a single hex digit from position 9 of the hash.
3. Result: `task-a3f8b2c19` (9 chars instead of 8).
4. This extends until uniqueness is achieved (up to the full 64-char hash).

## Status Transitions

Valid status values and their allowed transitions:

```
  null ──→ pending
              │
              ▼
         in_progress
              │
              ▼
          completed

  (any) ──→ removed
```

| From         | To           | Trigger                              |
|-------------|-------------|--------------------------------------|
| (new task)  | pending     | Task first appears in TodoWrite.     |
| pending     | in_progress | Task status set to "in progress".    |
| in_progress | completed   | Task status set to "completed".      |
| (any)       | removed     | Task disappears from TodoWrite list. |

**Notes:**
- There is no backward transition. A completed task cannot return to in_progress.
- "removed" is a terminal state recorded in history but the task object is deleted from tasks.json.
- "blocked" is not a formal status. Use the `dependencies` field and tags to represent blocked state.

## history.jsonl

Append-only log of all state transitions. Located at `.tasks/history.jsonl`. One JSON object per line.

### Entry format

```json
{"timestamp":"2026-03-17T11:30:00.000Z","task_id":"task-a3f8b2c1","transition":"pending→in_progress","content":"Implement JWT authentication","session_id":"abc123"}
```

| Field       | Type   | Description                                          |
|------------|--------|------------------------------------------------------|
| timestamp  | string | ISO 8601 timestamp of the transition.                |
| task_id    | string | Task ID that changed.                                |
| transition | string | Status change in "from→to" format.                   |
| content    | string | Task content at the time of transition.              |
| session_id | string | Session that triggered the transition.               |

**Properties:**
- Append-only. Lines are never modified or deleted.
- Used for audit, progress generation, and debugging.
- Can be safely truncated from the top (oldest entries) if the file grows large.

## progress.md

Narrative session summaries. Located at `.tasks/progress.md`. Human-readable markdown.

### Structure

The file uses **append-prepend** ordering: the newest session block is at the top.

```markdown
# Task Progress

## Session (2026-03-17)

### Completed
- Implemented JWT authentication (httpOnly cookies, 15-min expiry, refresh token rotation)

### In Progress
- Frontend login form — basic structure done, validation pending

### Blocked
- Email verification — waiting on SMTP credentials from user

### Key Decisions
- Chose JWT over session cookies because API serves both web and mobile

### Next Steps
1. Complete form validation
2. Wire forgot-password flow

---

## Session (2026-03-16)
...
```

Each session block follows the template in `assets/progress-template.md`. The horizontal rule (`---`) separates session blocks.

When generating a new session block, prepend it immediately after the `# Task Progress` heading, above any existing session blocks.
