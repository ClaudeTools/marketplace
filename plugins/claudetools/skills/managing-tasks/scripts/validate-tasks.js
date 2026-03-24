#!/usr/bin/env node
'use strict';

const path = require('path');
const fs = require('fs');

const { getTasksDir, generateTaskId } = require(path.join(__dirname, '..', '..', '..', 'scripts', 'lib', 'task-store.js'));

/**
 * Schema validation + circular dependency detection for tasks.json.
 *
 * Usage: node validate-tasks.js [path-to-tasks-dir]
 *   Exit 0 = valid  (stdout: {"valid": true, "task_count": N})
 *   Exit 1 = errors (stderr: {"valid": false, "errors": [...], "count": N})
 */

const VALID_STATUSES = new Set(['pending', 'in_progress', 'completed', 'removed']);
const VALID_PRIORITIES = new Set(['critical', 'high', 'medium', 'low']);

function isValidISO8601(str) {
  if (typeof str !== 'string') return false;
  const ts = Date.parse(str);
  return !isNaN(ts);
}

function isArray(val) {
  return Array.isArray(val);
}

/**
 * Detect circular dependencies using Kahn's algorithm (topological sort).
 * Returns an array of task IDs involved in cycles, or empty if no cycles.
 */
function detectCycles(tasks) {
  const taskIds = new Set(tasks.map(t => t.id));
  const inDegree = new Map();
  const adjacency = new Map(); // adjacency[dep] = [tasks that depend on dep]

  for (const t of tasks) {
    if (!inDegree.has(t.id)) inDegree.set(t.id, 0);
    if (!adjacency.has(t.id)) adjacency.set(t.id, []);

    const deps = t.dependencies || [];
    for (const dep of deps) {
      if (!taskIds.has(dep)) continue; // skip invalid refs — caught elsewhere
      if (!adjacency.has(dep)) adjacency.set(dep, []);
      adjacency.get(dep).push(t.id);
      inDegree.set(t.id, (inDegree.get(t.id) || 0) + 1);
    }
  }

  // Kahn's: start with nodes that have in-degree 0
  const queue = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) queue.push(id);
  }

  let processed = 0;
  while (queue.length > 0) {
    const node = queue.shift();
    processed++;
    for (const neighbor of (adjacency.get(node) || [])) {
      const newDeg = inDegree.get(neighbor) - 1;
      inDegree.set(neighbor, newDeg);
      if (newDeg === 0) queue.push(neighbor);
    }
  }

  // Any nodes not processed are part of a cycle
  if (processed === taskIds.size) return [];

  const cycleNodes = [];
  for (const [id, deg] of inDegree) {
    if (deg > 0) cycleNodes.push(id);
  }
  return cycleNodes;
}

function validate(tasksDir) {
  const errors = [];
  const filePath = path.join(tasksDir, 'tasks.json');

  // Check 1: file exists and parses as valid JSON
  if (!fs.existsSync(filePath)) {
    errors.push('tasks.json not found at ' + filePath);
    return errors;
  }

  let data;
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    data = JSON.parse(raw);
  } catch (e) {
    errors.push('tasks.json is not valid JSON: ' + e.message);
    return errors;
  }

  // Check 2: version field
  if (data.version === undefined || data.version === null) {
    errors.push('Missing required field: version');
  } else if (data.version !== 1) {
    errors.push('Unsupported version: ' + data.version + ' (expected 1)');
  }

  // Check 3: tasks array exists
  if (!isArray(data.tasks)) {
    errors.push('Missing or invalid field: tasks (expected array)');
    return errors;
  }

  const taskIds = new Set(data.tasks.map(t => t.id));
  const REQUIRED_FIELDS = ['id', 'content', 'status', 'created_at'];

  for (let i = 0; i < data.tasks.length; i++) {
    const task = data.tasks[i];
    const prefix = `tasks[${i}]`;

    // Check 4: required fields
    for (const field of REQUIRED_FIELDS) {
      if (task[field] === undefined || task[field] === null) {
        errors.push(`${prefix}: missing required field "${field}"`);
      }
    }

    if (!task.id || !task.content) continue; // skip further checks without id/content

    // Check 5: ID matches expected hash
    const expectedId = generateTaskId(task.content, []);
    // expectedId is the base form: task-{hex8}
    // Allow exact match OR collision-suffixed form: task-{hex8}-{N}
    const baseHash = expectedId; // e.g. task-abcd1234
    const idMatchesBase = task.id === baseHash;
    const idMatchesCollision = /^task-[0-9a-f]{8}-\d+$/.test(task.id) &&
      task.id.startsWith(baseHash.substring(0, 13)); // task- + 8 hex = 13 chars
    if (!idMatchesBase && !idMatchesCollision) {
      errors.push(`${prefix}: ID "${task.id}" does not match expected hash of content (expected "${expectedId}" or collision-suffixed form)`);
    }

    // Check 6: status enum
    if (task.status && !VALID_STATUSES.has(task.status)) {
      errors.push(`${prefix}: invalid status "${task.status}" (expected one of: ${[...VALID_STATUSES].join(', ')})`);
    }

    // Check 7: priority enum (if present)
    if (task.priority !== undefined && task.priority !== null && !VALID_PRIORITIES.has(task.priority)) {
      errors.push(`${prefix}: invalid priority "${task.priority}" (expected one of: ${[...VALID_PRIORITIES].join(', ')})`);
    }

    // Check 8: timestamps are valid ISO 8601
    if (task.created_at && !isValidISO8601(task.created_at)) {
      errors.push(`${prefix}: invalid created_at timestamp "${task.created_at}"`);
    }
    if (task.started_at && !isValidISO8601(task.started_at)) {
      errors.push(`${prefix}: invalid started_at timestamp "${task.started_at}"`);
    }
    if (task.completed_at && !isValidISO8601(task.completed_at)) {
      errors.push(`${prefix}: invalid completed_at timestamp "${task.completed_at}"`);
    }
    if (task.removed_at && !isValidISO8601(task.removed_at)) {
      errors.push(`${prefix}: invalid removed_at timestamp "${task.removed_at}"`);
    }

    // Check 9: dependencies reference existing task IDs
    if (task.dependencies) {
      if (!isArray(task.dependencies)) {
        errors.push(`${prefix}: dependencies must be an array`);
      } else {
        for (const dep of task.dependencies) {
          if (!taskIds.has(dep)) {
            errors.push(`${prefix}: dependency "${dep}" references non-existent task`);
          }
        }
      }
    }

    // Check 11: parent_id references existing task ID
    if (task.parent_id !== undefined && task.parent_id !== null) {
      if (!taskIds.has(task.parent_id)) {
        errors.push(`${prefix}: parent_id "${task.parent_id}" references non-existent task`);
      }
    }

    // Check 12: array fields are arrays if present
    if (task.tags !== undefined && task.tags !== null && !isArray(task.tags)) {
      errors.push(`${prefix}: tags must be an array`);
    }
    if (task.files_touched !== undefined && task.files_touched !== null && !isArray(task.files_touched)) {
      errors.push(`${prefix}: files_touched must be an array`);
    }
  }

  // Check 10: circular dependencies (Kahn's algorithm)
  const cycleNodes = detectCycles(data.tasks);
  if (cycleNodes.length > 0) {
    errors.push('Circular dependency detected involving tasks: ' + cycleNodes.join(', '));
  }

  return errors;
}

function main() {
  const tasksDir = process.argv[2] || getTasksDir();
  const errors = validate(tasksDir);

  if (errors.length === 0) {
    // Read task count for success output
    let taskCount = 0;
    try {
      const raw = fs.readFileSync(path.join(tasksDir, 'tasks.json'), 'utf8');
      const data = JSON.parse(raw);
      taskCount = (data.tasks || []).length;
    } catch (e) {
      // already validated, should not happen
    }
    process.stdout.write(JSON.stringify({ valid: true, task_count: taskCount }) + '\n');
    process.exit(0);
  } else {
    process.stderr.write(JSON.stringify({ valid: false, errors: errors, count: errors.length }) + '\n');
    process.exit(1);
  }
}

main();
