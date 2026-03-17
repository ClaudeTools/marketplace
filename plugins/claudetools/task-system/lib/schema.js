/**
 * Input validation for MCP tool parameters.
 */

const VALID_STATUSES = ['pending', 'in_progress', 'completed', 'removed'];
const VALID_PRIORITIES = ['critical', 'high', 'medium', 'low'];
const VALID_FORMATS = ['json', 'summary'];
const VALID_PROGRESS_ACTIONS = ['generate', 'append_session'];

function isNonEmptyString(val) {
  return typeof val === 'string' && val.trim().length > 0;
}

function isStringArray(val) {
  return Array.isArray(val) && val.every(item => typeof item === 'string');
}

/**
 * Validate task_create parameters.
 */
export function validateTaskCreate(args) {
  if (!args || typeof args !== 'object') {
    return { valid: false, error: 'field args: must be an object' };
  }
  if (!isNonEmptyString(args.content)) {
    return { valid: false, error: 'field content: required non-empty string' };
  }

  const sanitized = {
    content: args.content.trim(),
  };

  if (args.parent_id !== undefined) {
    if (!isNonEmptyString(args.parent_id)) {
      return { valid: false, error: 'field parent_id: must be a non-empty string' };
    }
    sanitized.parent_id = args.parent_id.trim();
  }

  if (args.dependencies !== undefined) {
    if (!isStringArray(args.dependencies)) {
      return { valid: false, error: 'field dependencies: must be an array of strings' };
    }
    sanitized.dependencies = args.dependencies;
  }

  if (args.tags !== undefined) {
    if (!isStringArray(args.tags)) {
      return { valid: false, error: 'field tags: must be an array of strings' };
    }
    sanitized.tags = args.tags;
  }

  if (args.priority !== undefined) {
    if (!VALID_PRIORITIES.includes(args.priority)) {
      return { valid: false, error: `field priority: must be one of ${VALID_PRIORITIES.join(', ')}` };
    }
    sanitized.priority = args.priority;
  }

  if (args.metadata !== undefined) {
    if (typeof args.metadata !== 'object' || args.metadata === null || Array.isArray(args.metadata)) {
      return { valid: false, error: 'field metadata: must be a plain object' };
    }
    sanitized.metadata = args.metadata;
  }

  const result = { valid: true, args: sanitized };

  if (sanitized.content.length < 200) {
    result.warning = 'Task content is very short. Consider adding acceptance criteria, file references, constraints, and verification commands.';
  }

  return result;
}

/**
 * Validate task_update parameters.
 */
export function validateTaskUpdate(args) {
  if (!args || typeof args !== 'object') {
    return { valid: false, error: 'field args: must be an object' };
  }
  if (!isNonEmptyString(args.id)) {
    return { valid: false, error: 'field id: required non-empty string' };
  }

  const sanitized = {
    id: args.id.trim(),
  };

  if (args.status !== undefined) {
    if (!VALID_STATUSES.includes(args.status)) {
      return { valid: false, error: `field status: must be one of ${VALID_STATUSES.join(', ')}` };
    }
    sanitized.status = args.status;
  }

  if (args.dependencies !== undefined) {
    if (!isStringArray(args.dependencies)) {
      return { valid: false, error: 'field dependencies: must be an array of strings' };
    }
    sanitized.dependencies = args.dependencies;
  }

  if (args.tags !== undefined) {
    if (!isStringArray(args.tags)) {
      return { valid: false, error: 'field tags: must be an array of strings' };
    }
    sanitized.tags = args.tags;
  }

  if (args.files_touched !== undefined) {
    if (!isStringArray(args.files_touched)) {
      return { valid: false, error: 'field files_touched: must be an array of strings' };
    }
    sanitized.files_touched = args.files_touched;
  }

  if (args.metadata !== undefined) {
    if (typeof args.metadata !== 'object' || args.metadata === null || Array.isArray(args.metadata)) {
      return { valid: false, error: 'field metadata: must be a plain object' };
    }
    sanitized.metadata = args.metadata;
  }

  if (args.priority !== undefined) {
    if (!VALID_PRIORITIES.includes(args.priority)) {
      return { valid: false, error: `field priority: must be one of ${VALID_PRIORITIES.join(', ')}` };
    }
    sanitized.priority = args.priority;
  }

  return { valid: true, args: sanitized };
}

/**
 * Validate task_query parameters.
 */
export function validateTaskQuery(args) {
  if (!args || typeof args !== 'object') {
    return { valid: false, error: 'field args: must be an object' };
  }

  const sanitized = {};

  if (args.status !== undefined) {
    if (typeof args.status !== 'string') {
      return { valid: false, error: 'field status: must be a string' };
    }
    sanitized.status = args.status;
  }

  if (args.tag !== undefined) {
    if (typeof args.tag !== 'string') {
      return { valid: false, error: 'field tag: must be a string' };
    }
    sanitized.tag = args.tag;
  }

  if (args.parent_id !== undefined) {
    if (typeof args.parent_id !== 'string') {
      return { valid: false, error: 'field parent_id: must be a string' };
    }
    sanitized.parent_id = args.parent_id;
  }

  if (args.has_blocker !== undefined) {
    if (typeof args.has_blocker !== 'boolean') {
      return { valid: false, error: 'field has_blocker: must be a boolean' };
    }
    sanitized.has_blocker = args.has_blocker;
  }

  if (args.format !== undefined) {
    if (!VALID_FORMATS.includes(args.format)) {
      return { valid: false, error: `field format: must be one of ${VALID_FORMATS.join(', ')}` };
    }
    sanitized.format = args.format;
  }

  return { valid: true, args: sanitized };
}

/**
 * Validate task_decompose parameters.
 */
export function validateTaskDecompose(args) {
  if (!args || typeof args !== 'object') {
    return { valid: false, error: 'field args: must be an object' };
  }
  if (!isNonEmptyString(args.id)) {
    return { valid: false, error: 'field id: required non-empty string' };
  }

  const sanitized = {
    id: args.id.trim(),
    max_subtasks: 5,
  };

  if (args.max_subtasks !== undefined) {
    if (typeof args.max_subtasks !== 'number' || !Number.isInteger(args.max_subtasks) || args.max_subtasks < 1) {
      return { valid: false, error: 'field max_subtasks: must be a positive integer' };
    }
    sanitized.max_subtasks = args.max_subtasks;
  }

  return { valid: true, args: sanitized };
}

/**
 * Validate task_progress parameters.
 */
export function validateTaskProgress(args) {
  if (!args || typeof args !== 'object') {
    return { valid: false, error: 'field args: must be an object' };
  }
  if (!VALID_PROGRESS_ACTIONS.includes(args.action)) {
    return { valid: false, error: `field action: required, must be one of ${VALID_PROGRESS_ACTIONS.join(', ')}` };
  }

  return { valid: true, args: { action: args.action } };
}
