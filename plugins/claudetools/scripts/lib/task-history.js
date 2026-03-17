#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Shared task history module.
 * Appends transition entries to history.jsonl.
 * Zero npm dependencies — Node.js builtins only.
 */

/**
 * Append transition entries to history.jsonl.
 * Each entry is a single-line JSON object.
 *
 * @param {string} tasksDir - Path to the .tasks/ directory
 * @param {Array} transitions - Array of {task_id, transition, content}
 * @param {string} [sessionId] - Optional session ID
 */
function appendHistory(tasksDir, transitions, sessionId) {
  if (!transitions || transitions.length === 0) return;

  fs.mkdirSync(tasksDir, { recursive: true });
  const filePath = path.join(tasksDir, 'history.jsonl');
  const now = new Date().toISOString();

  const lines = transitions.map(t => JSON.stringify({
    timestamp: now,
    task_id: t.task_id,
    transition: t.transition,
    content: t.content,
    session_id: sessionId || null
  }));

  fs.appendFileSync(filePath, lines.join('\n') + '\n');
}

/**
 * Read history.jsonl and return an array of parsed entries.
 *
 * @param {string} tasksDir - Path to the .tasks/ directory
 * @returns {Array} Parsed history entries
 */
function readHistory(tasksDir) {
  const filePath = path.join(tasksDir, 'history.jsonl');
  if (!fs.existsSync(filePath)) return [];

  try {
    const raw = fs.readFileSync(filePath, 'utf8').trim();
    if (!raw) return [];
    return raw.split('\n')
      .filter(line => line.trim())
      .map(line => {
        try { return JSON.parse(line); }
        catch { return null; }
      })
      .filter(Boolean);
  } catch (e) {
    process.stderr.write(`task-history: failed to read history.jsonl: ${e.message}\n`);
    return [];
  }
}

module.exports = {
  appendHistory,
  readHistory
};
