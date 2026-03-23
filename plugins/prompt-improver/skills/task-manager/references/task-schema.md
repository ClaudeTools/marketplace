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
| completed_at  | string       | null       | yes      | hook        | ISO 8601 timestamp when status became "completed".         |
| metadata      | object       | {}         | no       | MCP/skill   | Arbitrary key-value pairs for extensibility.               |

## ID Generation

Task IDs are deterministic, derived from the task content:

1. Take the `content` string.
2. Compute SHA-256 hash.
3. Truncate to the first 8 hexadecimal characters.
4. Prefix with `task-`.

Result: `task-a3f8b2c1`

**Same content always produces the same ID.** This makes the hook idempotent.

### Collision handling

If two different content strings produce the same 8-char prefix, the hook appends a monotonic counter: `task-a3f8b2c1-2`.

## Status Transitions

```
  null --> pending --> in_progress --> completed
  (any) --> removed
```

## history.jsonl

Append-only log. One JSON object per line:

```json
{"timestamp":"...","task_id":"task-a3f8b2c1","transition":"pending->in_progress","content":"...","session_id":"..."}
```

## progress.md

Narrative session summaries. Append-prepend ordering (newest at top).
