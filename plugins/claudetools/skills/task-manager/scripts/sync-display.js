#!/usr/bin/env node
'use strict';

const path = require('path');

const { getTasksDir, readTasks } = require(path.join(__dirname, '..', '..', '..', 'scripts', 'lib', 'task-store.js'));

/**
 * Converts tasks.json into TodoWrite format for session restoration.
 *
 * Usage: node sync-display.js [path-to-tasks-dir]
 *
 * stdout: JSON array of [{content, status, activeForm}, ...]
 * stderr: summary like "Restored N tasks (X in_progress, Y pending, Z completed)"
 */

// Sort order: in_progress first, then pending, then completed
const STATUS_ORDER = { in_progress: 0, pending: 1, completed: 2 };

function main() {
  const tasksDir = process.argv[2] || getTasksDir();
  const data = readTasks(tasksDir);
  const tasks = data.tasks || [];

  // Filter out removed tasks
  const visible = tasks.filter(t => t.status !== 'removed');

  // Sort: in_progress first, then pending, then completed
  visible.sort((a, b) => {
    const orderA = STATUS_ORDER[a.status] !== undefined ? STATUS_ORDER[a.status] : 99;
    const orderB = STATUS_ORDER[b.status] !== undefined ? STATUS_ORDER[b.status] : 99;
    return orderA - orderB;
  });

  // Map to TodoWrite format
  const todoItems = visible.map(t => ({
    content: t.content,
    status: t.status,
    activeForm: t.active_form || t.content
  }));

  // Count by status
  let inProgress = 0;
  let pending = 0;
  let completed = 0;

  for (const t of visible) {
    if (t.status === 'in_progress') inProgress++;
    else if (t.status === 'pending') pending++;
    else if (t.status === 'completed') completed++;
  }

  // Output
  process.stdout.write(JSON.stringify(todoItems, null, 2) + '\n');
  process.stderr.write(`Restored ${visible.length} tasks (${inProgress} in_progress, ${pending} pending, ${completed} completed)\n`);
}

main();
