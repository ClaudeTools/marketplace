#!/usr/bin/env node
'use strict';

/**
 * PostToolUse:TodoWrite hook.
 * Reads stdin JSON, diffs against tasks.json, writes transitions.
 *
 * Requirements:
 * - MUST complete in under 100ms
 * - MUST be idempotent
 * - MUST NOT use any npm dependencies (Node.js builtins only)
 * - MUST create .tasks/ if it does not exist
 * - MUST handle malformed input gracefully
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Import shared modules
const { getTasksDir, readTasks, writeTasks, diffTodos } = require(
  path.join(__dirname, 'lib', 'task-store.js')
);
const { appendHistory } = require(
  path.join(__dirname, 'lib', 'task-history.js')
);

// --- Read stdin synchronously ---
let input;
try {
  input = fs.readFileSync('/dev/stdin', 'utf8');
} catch (e) {
  process.stderr.write('Hook error: failed to read stdin\n');
  process.exit(1);
}

let payload;
try {
  payload = JSON.parse(input);
} catch (e) {
  process.stderr.write('Hook error: invalid JSON on stdin\n');
  process.exit(1);
}

// Extract todos array from the payload
const todos = payload.tool_input?.todos || payload.todos || [];
if (!Array.isArray(todos)) {
  process.stderr.write('Hook error: todos is not an array\n');
  process.exit(1);
}

// --- Derive session ID ---
const sessionId = process.env.CLAUDE_SESSION_ID
  || 'session-' + crypto.createHash('sha256')
      .update(String(process.ppid) + String(Date.now()))
      .digest('hex').substring(0, 8);

// --- Resolve .tasks/ directory ---
const tasksDir = getTasksDir(process.cwd());
fs.mkdirSync(tasksDir, { recursive: true });

// --- Read existing state ---
const existingData = readTasks(tasksDir);

// --- Diff incoming todos against existing tasks ---
const { updatedTasks, transitions } = diffTodos(todos, existingData);

// --- Write updated state ---
if (transitions.length > 0) {
  const updatedData = {
    ...existingData,
    session_id: sessionId,
    project: existingData.project || path.basename(process.cwd()),
    tasks: updatedTasks,
  };
  writeTasks(tasksDir, updatedData);
  appendHistory(tasksDir, transitions, sessionId);
}

process.exit(0);
