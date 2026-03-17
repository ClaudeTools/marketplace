#!/usr/bin/env node
'use strict';

const path = require('path');

const { getTasksDir, readTasks } = require(path.join(__dirname, '..', '..', '..', 'scripts', 'lib', 'task-store.js'));
const { readHistory } = require(path.join(__dirname, '..', '..', '..', 'scripts', 'lib', 'task-history.js'));

/**
 * Task status reports. Deterministic structure, data-driven content.
 *
 * Usage: node task-report.js [path-to-tasks-dir] [--format markdown|json|summary]
 *                            [--include-completed] [--include-history]
 */

function parseArgs(argv) {
  const args = {
    tasksDir: null,
    format: 'markdown',
    includeCompleted: false,
    includeHistory: false
  };

  let i = 2; // skip node and script path
  while (i < argv.length) {
    const arg = argv[i];
    if (arg === '--format' && i + 1 < argv.length) {
      args.format = argv[i + 1];
      i += 2;
    } else if (arg === '--include-completed') {
      args.includeCompleted = true;
      i++;
    } else if (arg === '--include-history') {
      args.includeHistory = true;
      i++;
    } else if (!arg.startsWith('--')) {
      args.tasksDir = arg;
      i++;
    } else {
      i++;
    }
  }

  if (!args.tasksDir) {
    args.tasksDir = getTasksDir();
  }

  return args;
}

/**
 * Format a duration in milliseconds as "Xd Yh Zm".
 */
function formatDuration(ms) {
  if (ms <= 0) return '0m';

  const minutes = Math.floor(ms / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  const remHours = hours % 24;
  const remMinutes = minutes % 60;

  const parts = [];
  if (days > 0) parts.push(days + 'd');
  if (remHours > 0) parts.push(remHours + 'h');
  if (remMinutes > 0 || parts.length === 0) parts.push(remMinutes + 'm');

  return parts.join(' ');
}

/**
 * Determine if a task is blocked: has dependencies where not all are completed.
 */
function isBlocked(task, taskMap) {
  if (!task.dependencies || task.dependencies.length === 0) return false;
  if (task.status === 'completed' || task.status === 'removed') return false;
  return task.dependencies.some(depId => {
    const dep = taskMap.get(depId);
    return !dep || dep.status !== 'completed';
  });
}

/**
 * Build computed stats from tasks array.
 */
function computeStats(tasks, taskMap) {
  const now = Date.now();
  let pending = 0;
  let inProgress = 0;
  let completed = 0;
  let blocked = 0;

  const activeTasks = tasks.filter(t => t.status !== 'removed');

  for (const t of activeTasks) {
    if (isBlocked(t, taskMap)) {
      blocked++;
    } else if (t.status === 'pending') {
      pending++;
    } else if (t.status === 'in_progress') {
      inProgress++;
    } else if (t.status === 'completed') {
      completed++;
    }
  }

  // Pending count: tasks counted as blocked are removed from pending/in_progress tallies
  // Re-count: blocked tasks may have status pending or in_progress
  // Adjust: we double-counted blocked tasks in pending/in_progress above — no, we used else-if
  // Actually blocked is only counted when isBlocked returns true, then we skip the status check.
  // So pending, inProgress, completed are only for non-blocked tasks.

  const total = activeTasks.length;
  const completionRate = total > 0 ? Math.round((completed / total) * 100) : 0;

  return { total, pending, in_progress: inProgress, completed, blocked, completion_rate: completionRate };
}

function generateMarkdown(data, stats, taskMap, args) {
  const now = new Date().toISOString();
  const projectName = data.project || 'Unknown Project';
  const tasks = data.tasks.filter(t => t.status !== 'removed');
  const currentTime = Date.now();

  const lines = [];
  lines.push(`# Task Report - ${projectName}`);
  lines.push(`Generated: ${now}`);
  lines.push('');

  // Summary
  lines.push('## Summary');
  lines.push(`Total: ${stats.total} | Pending: ${stats.pending} | In Progress: ${stats.in_progress} | Completed: ${stats.completed} | Blocked: ${stats.blocked}`);
  lines.push(`Completion rate: ${stats.completion_rate}%`);
  lines.push('');

  // Active Tasks
  const active = tasks.filter(t =>
    (t.status === 'in_progress' || t.status === 'pending') && !isBlocked(t, taskMap)
  );
  lines.push('## Active Tasks');
  if (active.length === 0) {
    lines.push('No active tasks.');
  } else {
    lines.push('| ID | Task | Status | Priority | Duration |');
    lines.push('|---|---|---|---|---|');
    for (const t of active) {
      const startMs = t.started_at ? Date.parse(t.started_at) : Date.parse(t.created_at);
      const duration = formatDuration(currentTime - startMs);
      const shortId = t.id.length > 13 ? t.id.substring(0, 13) : t.id;
      lines.push(`| ${shortId} | ${t.content} | ${t.status} | ${t.priority || 'medium'} | ${duration} |`);
    }
  }
  lines.push('');

  // Blocked Tasks
  const blockedTasks = tasks.filter(t => isBlocked(t, taskMap));
  lines.push('## Blocked Tasks');
  if (blockedTasks.length === 0) {
    lines.push('No blocked tasks.');
  } else {
    for (const t of blockedTasks) {
      const waitingOn = (t.dependencies || [])
        .filter(depId => {
          const dep = taskMap.get(depId);
          return !dep || dep.status !== 'completed';
        })
        .map(depId => {
          const dep = taskMap.get(depId);
          return dep ? dep.content : depId;
        });
      lines.push(`- ${t.content} — waiting on: ${waitingOn.join(', ')}`);
    }
  }
  lines.push('');

  // Completed Tasks
  if (args.includeCompleted) {
    const completedTasks = tasks.filter(t => t.status === 'completed');
    lines.push('## Completed Tasks');
    if (completedTasks.length === 0) {
      lines.push('No completed tasks.');
    } else {
      for (const t of completedTasks) {
        const startMs = t.started_at ? Date.parse(t.started_at) : Date.parse(t.created_at);
        const endMs = t.completed_at ? Date.parse(t.completed_at) : currentTime;
        const duration = formatDuration(endMs - startMs);
        lines.push(`- ${t.content} (${duration})`);
      }
    }
    lines.push('');
  }

  // Recent History
  if (args.includeHistory) {
    const history = readHistory(args.tasksDir);
    const recent = history.slice(-20);
    lines.push('## Recent History');
    if (recent.length === 0) {
      lines.push('No history entries.');
    } else {
      for (const entry of recent) {
        const time = entry.timestamp || 'unknown';
        const content = entry.content || entry.task_id;
        const transition = entry.transition || 'unknown';
        lines.push(`- ${time} ${content}: ${transition}`);
      }
    }
    lines.push('');
  }

  return lines.join('\n');
}

function generateSummary(stats) {
  return `${stats.total} tasks: ${stats.in_progress} active, ${stats.pending} pending, ${stats.completed} done, ${stats.blocked} blocked (${stats.completion_rate}% complete)`;
}

function generateJSON(data, stats) {
  const tasks = data.tasks.filter(t => t.status !== 'removed');
  return JSON.stringify({ stats, tasks }, null, 2);
}

function main() {
  const args = parseArgs(process.argv);
  const data = readTasks(args.tasksDir);
  const tasks = data.tasks || [];

  // Build task lookup map
  const taskMap = new Map();
  for (const t of tasks) {
    taskMap.set(t.id, t);
  }

  const stats = computeStats(tasks, taskMap);

  let output;
  switch (args.format) {
    case 'json':
      output = generateJSON(data, stats);
      break;
    case 'summary':
      output = generateSummary(stats);
      break;
    case 'markdown':
    default:
      output = generateMarkdown(data, stats, taskMap, args);
      break;
  }

  process.stdout.write(output + '\n');
}

main();
