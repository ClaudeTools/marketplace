import { createRequire } from 'module';
import {
  validateTaskCreate,
  validateTaskUpdate,
  validateTaskQuery,
  validateTaskDecompose,
  validateTaskProgress,
} from './schema.js';

const require = createRequire(import.meta.url);
const { getTasksDir, readTasks, writeTasks, generateTaskId, createTask } = require('../../scripts/lib/task-store.js');
const { appendHistory, readHistory } = require('../../scripts/lib/task-history.js');

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

export const TOOLS = [
  {
    name: 'task_create',
    description:
      'Create a new task with optional metadata. Returns the created task ID, content, and status. Content should be a comprehensive, self-contained task description — not a one-liner. Include: title, description, acceptance criteria (verb-led, measurable), file references, constraints, verification commands.',
    inputSchema: {
      type: 'object',
      properties: {
        content: {
          type: 'string',
          description: 'Comprehensive task description. Structure with sections: Title, Description, Acceptance Criteria (verb-led, measurable), File References (read/modify/do-not-touch with real paths), Constraints, Out of Scope, Verification (exact shell commands), Risk Level.',
        },
        parent_id: {
          type: 'string',
          description: 'Parent task ID for subtasks',
        },
        dependencies: {
          type: 'array',
          items: { type: 'string' },
          description: 'Array of task IDs this task depends on',
        },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Tags for categorization',
        },
        priority: {
          type: 'string',
          enum: ['critical', 'high', 'medium', 'low'],
          description: 'Task priority (default: medium)',
        },
        metadata: {
          type: 'object',
          description: 'Structured metadata. Recommended fields: file_references, acceptance_criteria, verification_commands, reference_patterns, out_of_scope, risk_level.',
        },
      },
      required: ['content'],
    },
  },
  {
    name: 'task_update',
    description:
      'Update an existing task. Can change status, dependencies, tags, files_touched, metadata, or priority. Returns updated field names.',
    inputSchema: {
      type: 'object',
      properties: {
        id: {
          type: 'string',
          description: 'Task ID to update (required)',
        },
        status: {
          type: 'string',
          enum: ['pending', 'in_progress', 'completed', 'removed'],
          description: 'New status for the task',
        },
        dependencies: {
          type: 'array',
          items: { type: 'string' },
          description: 'Updated dependency task IDs',
        },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Updated tags',
        },
        files_touched: {
          type: 'array',
          items: { type: 'string' },
          description: 'Files modified while working on this task',
        },
        metadata: {
          type: 'object',
          description: 'Arbitrary metadata to merge into the task',
        },
        priority: {
          type: 'string',
          enum: ['critical', 'high', 'medium', 'low'],
          description: 'Updated priority',
        },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_query',
    description:
      'Query tasks with filters. Can filter by status, tag, parent_id, or blocked state. Returns JSON array or a text summary.',
    inputSchema: {
      type: 'object',
      properties: {
        status: {
          type: 'string',
          description: 'Filter by status (pending, in_progress, completed, removed)',
        },
        tag: {
          type: 'string',
          description: 'Filter by tag (matches if task has this tag)',
        },
        parent_id: {
          type: 'string',
          description: 'Filter by parent task ID',
        },
        has_blocker: {
          type: 'boolean',
          description: 'If true, only return tasks with unfinished dependencies',
        },
        format: {
          type: 'string',
          enum: ['json', 'summary'],
          description: 'Output format (default: json)',
        },
      },
    },
  },
  {
    name: 'task_decompose',
    description:
      'Get context for decomposing a task into subtasks. Returns the parent task, existing subtasks, and decomposition guidance including codebase-pilot instructions.',
    inputSchema: {
      type: 'object',
      properties: {
        id: {
          type: 'string',
          description: 'Task ID to decompose (required)',
        },
        max_subtasks: {
          type: 'number',
          description: 'Maximum number of subtasks to suggest (default: 5)',
        },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_progress',
    description:
      'Get task progress data. "generate" returns full tasks + history for a narrative report. "append_session" returns current session counts.',
    inputSchema: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: ['generate', 'append_session'],
          description: 'Action to perform (required)',
        },
      },
      required: ['action'],
    },
  },
];

// ---------------------------------------------------------------------------
// Tool handlers
// ---------------------------------------------------------------------------

async function handleTaskCreate(args, projectRoot) {
  const validation = validateTaskCreate(args);
  if (!validation.valid) {
    return { isError: true, error: validation.error };
  }
  const v = validation.args;

  const tasksDir = getTasksDir(projectRoot);
  const data = readTasks(tasksDir);

  const id = generateTaskId(v.content, data.tasks);
  const task = createTask(v.content, null, id);

  // Apply optional fields
  if (v.parent_id) task.parent_id = v.parent_id;
  if (v.dependencies) task.dependencies = v.dependencies;
  if (v.tags) task.tags = v.tags;
  if (v.priority) task.priority = v.priority;
  if (v.metadata) task.metadata = v.metadata;

  data.tasks.push(task);
  writeTasks(tasksDir, data);

  appendHistory(tasksDir, [{
    task_id: id,
    transition: 'null->pending',
    content: v.content,
  }]);

  const result = { id, content: v.content, status: 'pending' };
  if (validation.warning) {
    result.warning = validation.warning;
  }
  return result;
}

async function handleTaskUpdate(args, projectRoot) {
  const validation = validateTaskUpdate(args);
  if (!validation.valid) {
    return { isError: true, error: validation.error };
  }
  const v = validation.args;

  const tasksDir = getTasksDir(projectRoot);
  const data = readTasks(tasksDir);

  const taskIndex = data.tasks.findIndex(t => t.id === v.id);
  if (taskIndex === -1) {
    return { isError: true, error: `Task not found: ${v.id}` };
  }

  const task = data.tasks[taskIndex];
  const updatedFields = [];
  const transitions = [];

  // Status change with timestamp tracking
  if (v.status !== undefined && v.status !== task.status) {
    const oldStatus = task.status;
    task.status = v.status;
    updatedFields.push('status');

    if (v.status === 'in_progress' && !task.started_at) {
      task.started_at = new Date().toISOString();
    }
    if (v.status === 'completed') {
      task.completed_at = new Date().toISOString();
    }
    if (v.status === 'removed') {
      task.removed_at = new Date().toISOString();
    }

    transitions.push({
      task_id: v.id,
      transition: `${oldStatus}->${v.status}`,
      content: task.content,
    });
  }

  if (v.dependencies !== undefined) {
    task.dependencies = v.dependencies;
    updatedFields.push('dependencies');
  }
  if (v.tags !== undefined) {
    task.tags = v.tags;
    updatedFields.push('tags');
  }
  if (v.files_touched !== undefined) {
    task.files_touched = v.files_touched;
    updatedFields.push('files_touched');
  }
  if (v.metadata !== undefined) {
    task.metadata = { ...task.metadata, ...v.metadata };
    updatedFields.push('metadata');
  }
  if (v.priority !== undefined) {
    task.priority = v.priority;
    updatedFields.push('priority');
  }

  data.tasks[taskIndex] = task;
  writeTasks(tasksDir, data);

  if (transitions.length > 0) {
    appendHistory(tasksDir, transitions);
  }

  return { id: v.id, updated_fields: updatedFields };
}

async function handleTaskQuery(args, projectRoot) {
  const validation = validateTaskQuery(args);
  if (!validation.valid) {
    return { isError: true, error: validation.error };
  }
  const v = validation.args;

  const tasksDir = getTasksDir(projectRoot);
  const data = readTasks(tasksDir);
  let filtered = data.tasks;

  // Apply filters
  if (v.status !== undefined) {
    filtered = filtered.filter(t => t.status === v.status);
  }
  if (v.tag !== undefined) {
    filtered = filtered.filter(t => t.tags && t.tags.includes(v.tag));
  }
  if (v.parent_id !== undefined) {
    filtered = filtered.filter(t => t.parent_id === v.parent_id);
  }
  if (v.has_blocker === true) {
    filtered = filtered.filter(t => {
      if (!t.dependencies || t.dependencies.length === 0) return false;
      // Has blocker if any dependency is NOT completed
      return t.dependencies.some(depId => {
        const dep = data.tasks.find(d => d.id === depId);
        return !dep || dep.status !== 'completed';
      });
    });
  } else if (v.has_blocker === false) {
    filtered = filtered.filter(t => {
      if (!t.dependencies || t.dependencies.length === 0) return true;
      // Not blocked: all dependencies are completed
      return t.dependencies.every(depId => {
        const dep = data.tasks.find(d => d.id === depId);
        return dep && dep.status === 'completed';
      });
    });
  }

  const format = v.format || 'json';

  if (format === 'summary') {
    const total = filtered.length;
    const byStatus = {};
    for (const t of filtered) {
      byStatus[t.status] = (byStatus[t.status] || 0) + 1;
    }
    const lines = [`${total} task(s) matched:`];
    for (const [status, count] of Object.entries(byStatus)) {
      lines.push(`  ${status}: ${count}`);
    }
    if (total > 0) {
      lines.push('');
      for (const t of filtered) {
        const tags = t.tags && t.tags.length > 0 ? ` [${t.tags.join(', ')}]` : '';
        const priority = t.priority ? ` (${t.priority})` : '';
        lines.push(`  ${t.id} [${t.status}]${priority}${tags}: ${t.content}`);
      }
    }
    return lines.join('\n');
  }

  // Default: json
  return filtered;
}

async function handleTaskDecompose(args, projectRoot) {
  const validation = validateTaskDecompose(args);
  if (!validation.valid) {
    return { isError: true, error: validation.error };
  }
  const v = validation.args;

  const tasksDir = getTasksDir(projectRoot);
  const data = readTasks(tasksDir);

  const task = data.tasks.find(t => t.id === v.id);
  if (!task) {
    return { isError: true, error: `Task not found: ${v.id}` };
  }

  // Find existing subtasks
  const existingSubtasks = data.tasks
    .filter(t => t.parent_id === v.id)
    .map(t => ({
      id: t.id,
      content: t.content,
      status: t.status,
    }));

  const result = {
    parent_id: v.id,
    parent_content: task.content,
    existing_subtasks: existingSubtasks,
    max_subtasks: v.max_subtasks,
  };

  // Only include guidance on first decomposition (no subtasks yet)
  if (existingSubtasks.length === 0) {
    result.decomposition_guidance = {
      context_gathering: 'Use codebase-pilot MCP tools before creating subtasks: project_map to orient, find_symbol to locate functions/classes, file_overview to understand file structure, related_files to discover dependencies. Use REAL paths from these tools — do not invent file paths.',
      subtask_structure: 'Each subtask must include: Title, Description, Acceptance Criteria (verb-led, measurable, ≥2 items), File References (read/modify/do-not-touch with real paths, ≥1), Constraints, Out of Scope, Verification (exact shell commands, ≥1), Risk Level.',
      completeness: 'Create ALL subtasks upfront — not just the first phase. Verification, testing, polish, and documentation tasks require the same depth as implementation tasks. Do not defer later phases.',
      anti_deferral: 'Create all phases with equal detail. A task an agent cannot execute autonomously is not a task — it is a reminder.',
    };
  }

  return result;
}

async function handleTaskProgress(args, projectRoot) {
  const validation = validateTaskProgress(args);
  if (!validation.valid) {
    return { isError: true, error: validation.error };
  }
  const v = validation.args;

  const tasksDir = getTasksDir(projectRoot);
  const data = readTasks(tasksDir);

  if (v.action === 'generate') {
    const history = readHistory(tasksDir);
    return {
      action: 'generate',
      tasks: data.tasks,
      history,
      summary: {
        total: data.tasks.length,
        pending: data.tasks.filter(t => t.status === 'pending').length,
        in_progress: data.tasks.filter(t => t.status === 'in_progress').length,
        completed: data.tasks.filter(t => t.status === 'completed').length,
        removed: data.tasks.filter(t => t.status === 'removed').length,
      },
      last_updated: data.last_updated,
    };
  }

  // action === 'append_session'
  const completed = data.tasks.filter(t => t.status === 'completed').length;
  const inProgress = data.tasks.filter(t => t.status === 'in_progress').length;
  const blocked = data.tasks.filter(t => {
    if (!t.dependencies || t.dependencies.length === 0) return false;
    return t.dependencies.some(depId => {
      const dep = data.tasks.find(d => d.id === depId);
      return !dep || dep.status !== 'completed';
    });
  }).length;

  return {
    action: 'append_session',
    session_data: {
      timestamp: new Date().toISOString(),
      completed_count: completed,
      in_progress_count: inProgress,
      blocked_count: blocked,
      total_count: data.tasks.length,
    },
  };
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

export async function handleToolCall(name, args, projectRoot) {
  switch (name) {
    case 'task_create':
      return handleTaskCreate(args, projectRoot);
    case 'task_update':
      return handleTaskUpdate(args, projectRoot);
    case 'task_query':
      return handleTaskQuery(args, projectRoot);
    case 'task_decompose':
      return handleTaskDecompose(args, projectRoot);
    case 'task_progress':
      return handleTaskProgress(args, projectRoot);
    default:
      return { isError: true, error: `Unknown tool: ${name}` };
  }
}
