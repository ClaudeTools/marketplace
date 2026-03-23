#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/**
 * Shared task store module.
 * Used by both the PostToolUse hook and the MCP server.
 * Zero npm dependencies — Node.js builtins only.
 */

const DEFAULT_DATA = () => ({
  version: 1,
  session_id: null,
  project: null,
  tasks: [],
  last_updated: new Date().toISOString()
});

/**
 * Resolve the .tasks/ directory relative to git root or cwd.
 */
function getTasksDir(cwd) {
  cwd = cwd || process.cwd();
  // Walk up to find git root
  let dir = cwd;
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, '.git'))) {
      return path.join(dir, '.tasks');
    }
    dir = path.dirname(dir);
  }
  // Fallback to cwd
  return path.join(cwd, '.tasks');
}

/**
 * Read tasks.json from the given tasks directory.
 * Returns the parsed data or a default structure if the file doesn't exist.
 */
function readTasks(tasksDir) {
  const filePath = path.join(tasksDir, 'tasks.json');
  if (!fs.existsSync(filePath)) {
    return DEFAULT_DATA();
  }
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (e) {
    process.stderr.write(`task-store: failed to read tasks.json: ${e.message}\n`);
    return DEFAULT_DATA();
  }
}

/**
 * Write tasks.json atomically (write to tmp file, then rename).
 */
function writeTasks(tasksDir, data) {
  fs.mkdirSync(tasksDir, { recursive: true });
  const filePath = path.join(tasksDir, 'tasks.json');
  const tmp = filePath + '.tmp.' + process.pid;
  data.last_updated = new Date().toISOString();
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, filePath);
}

/**
 * Generate a deterministic task ID from content using SHA-256 truncated to 8 hex chars.
 * Checks for collisions against existing tasks and appends a counter suffix if needed.
 */
function generateTaskId(content, existingTasks) {
  const hash = crypto.createHash('sha256').update(content).digest('hex');
  const baseId = 'task-' + hash.substring(0, 8);

  if (!existingTasks || existingTasks.length === 0) {
    return baseId;
  }

  // Check for collision (different content, same hash prefix)
  const collision = existingTasks.find(t => t.id === baseId && t.content !== content);
  if (!collision) {
    return baseId;
  }

  // Find next available suffix
  let counter = 2;
  while (existingTasks.some(t => t.id === `${baseId}-${counter}`)) {
    counter++;
  }
  return `${baseId}-${counter}`;
}

/**
 * Create a new task object with all default fields.
 */
function createTask(content, activeForm, id) {
  return {
    id: id,
    content: content,
    active_form: activeForm || null,
    status: 'pending',
    created_at: new Date().toISOString(),
    started_at: null,
    completed_at: null,
    removed_at: null,
    parent_id: null,
    dependencies: [],
    tags: [],
    priority: 'medium',
    files_touched: [],
    metadata: {}
  };
}

/**
 * Diff incoming TodoWrite array against existing tasks.
 * Returns { updatedTasks, transitions } where:
 *   - updatedTasks: the new full tasks array for tasks.json
 *   - transitions: array of {task_id, transition, content} for history.jsonl
 */
function diffTodos(incoming, existingData) {
  const existing = existingData.tasks || [];
  const transitions = [];
  const updatedTasks = [];
  const matchedExisting = new Set();

  for (const todo of incoming) {
    const content = todo.content;
    const status = todo.status || 'pending';
    const activeForm = todo.activeForm || null;

    // Find existing task by content match
    const existingTask = existing.find(t => t.content === content);

    if (!existingTask) {
      // NEW task
      const id = generateTaskId(content, existing.concat(updatedTasks));
      const task = createTask(content, activeForm, id);
      task.status = status;
      if (status === 'in_progress') {
        task.started_at = new Date().toISOString();
      } else if (status === 'completed') {
        task.started_at = task.started_at || new Date().toISOString();
        task.completed_at = new Date().toISOString();
      }
      updatedTasks.push(task);
      transitions.push({
        task_id: id,
        transition: `null->${status}`,
        content: content
      });
    } else {
      // EXISTING task — check for status change
      matchedExisting.add(existingTask.id);
      const updated = { ...existingTask, active_form: activeForm };

      if (existingTask.status !== status) {
        // Status changed
        updated.status = status;
        if (status === 'in_progress' && !updated.started_at) {
          updated.started_at = new Date().toISOString();
        }
        if (status === 'completed') {
          updated.completed_at = new Date().toISOString();
        }
        transitions.push({
          task_id: existingTask.id,
          transition: `${existingTask.status}->${status}`,
          content: content
        });
      }
      // No change — no transition recorded (idempotent)
      updatedTasks.push(updated);
    }
  }

  // Tasks in existing but NOT in incoming → mark as removed
  for (const task of existing) {
    if (!matchedExisting.has(task.id) && !updatedTasks.some(t => t.id === task.id)) {
      if (task.status !== 'removed') {
        const removed = { ...task, status: 'removed', removed_at: new Date().toISOString() };
        updatedTasks.push(removed);
        transitions.push({
          task_id: task.id,
          transition: `${task.status}->removed`,
          content: task.content
        });
      } else {
        // Already removed, keep as-is
        updatedTasks.push(task);
      }
    }
  }

  return { updatedTasks, transitions };
}

module.exports = {
  getTasksDir,
  readTasks,
  writeTasks,
  generateTaskId,
  createTask,
  diffTodos
};
