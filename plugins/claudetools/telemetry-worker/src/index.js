const MAX_LINES = 100;
const MAX_BODY_BYTES = 1_000_000; // 1MB
const MAX_FEEDBACK_BYTES = 102_400; // 100KB per feedback report (narrative fields need room)
const MAX_FEEDBACK_ITEMS = 50;
const VALID_CATEGORIES = ['false_positive', 'bug', 'missing_feature', 'workflow_gap', 'praise', 'suggestion'];
const VALID_SEVERITIES = ['critical', 'high', 'medium', 'low'];
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 50;

// In-memory rate limit store: { ip -> { count, windowStart } }
const rateLimitStore = new Map();

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimitStore.get(ip);

  if (!entry || now - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateLimitStore.set(ip, { count: 1, windowStart: now });
    return true;
  }

  if (entry.count >= RATE_LIMIT_MAX) {
    return false;
  }

  entry.count++;
  return true;
}

function validateEvent(obj) {
  return (
    obj &&
    typeof obj.ts === 'string' &&
    typeof obj.install_id === 'string' &&
    typeof obj.component === 'string' &&
    typeof obj.event === 'string'
  );
}

async function handlePostEvents(request, env) {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';

  if (!checkRateLimit(ip)) {
    return jsonResponse({ error: 'Rate limit exceeded' }, 429);
  }

  const contentLength = parseInt(request.headers.get('Content-Length') || '0', 10);
  if (contentLength > MAX_BODY_BYTES) {
    return jsonResponse({ error: 'Body too large' }, 413);
  }

  let body;
  try {
    body = await request.text();
  } catch {
    return jsonResponse({ error: 'Failed to read body' }, 400);
  }

  if (body.length > MAX_BODY_BYTES) {
    return jsonResponse({ error: 'Body too large' }, 413);
  }

  const lines = body.split('\n').filter((l) => l.trim().length > 0);

  if (lines.length > MAX_LINES) {
    return jsonResponse({ error: `Too many lines (max ${MAX_LINES})` }, 400);
  }

  const valid = [];
  let rejected = 0;

  for (const line of lines) {
    let obj;
    try {
      obj = JSON.parse(line);
    } catch {
      rejected++;
      continue;
    }

    if (!validateEvent(obj)) {
      rejected++;
      continue;
    }

    valid.push(obj);
  }

  if (valid.length === 0) {
    return jsonResponse({ accepted: 0, rejected });
  }

  // Batch insert using prepared statements
  const stmt = env.TELEMETRY_DB.prepare(
    `INSERT INTO events (ts, install_id, plugin_version, component, event, decision, duration_ms, model_family, os, extra)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );

  const batch = valid.map((e) =>
    stmt.bind(
      e.ts,
      e.install_id,
      e.plugin_version ?? null,
      e.component,
      e.event,
      e.decision ?? null,
      typeof e.duration_ms === 'number' ? e.duration_ms : 0,
      e.model_family ?? null,
      e.os ?? null,
      e.extra ? JSON.stringify(e.extra) : '{}'
    )
  );

  try {
    await env.TELEMETRY_DB.batch(batch);
  } catch (err) {
    return jsonResponse({ error: 'Database error', detail: err.message }, 500);
  }

  return jsonResponse({ accepted: valid.length, rejected });
}

async function handleGetStats(request, env) {
  try {
    const [totalResult, uniqueResult, decisionResult, componentResult] = await env.TELEMETRY_DB.batch([
      env.TELEMETRY_DB.prepare('SELECT COUNT(*) as total FROM events'),
      env.TELEMETRY_DB.prepare('SELECT COUNT(DISTINCT install_id) as unique_installs FROM events'),
      env.TELEMETRY_DB.prepare(
        `SELECT decision, COUNT(*) as count FROM events GROUP BY decision ORDER BY count DESC`
      ),
      env.TELEMETRY_DB.prepare(
        `SELECT component, COUNT(*) as count FROM events GROUP BY component ORDER BY count DESC LIMIT 20`
      ),
    ]);

    return jsonResponse({
      total_events: totalResult.results[0]?.total ?? 0,
      unique_installs: uniqueResult.results[0]?.unique_installs ?? 0,
      events_by_decision: decisionResult.results,
      top_components: componentResult.results,
    });
  } catch (err) {
    return jsonResponse({ error: 'Database error', detail: err.message }, 500);
  }
}

async function handleGetHooks(request, env) {
  const url = new URL(request.url);
  const days = parseInt(url.searchParams.get('days') || '7', 10);
  const safeDays = Number.isFinite(days) && days > 0 ? days : 7;

  const detail = url.searchParams.get('detail') === 'true';

  try {
    const query = detail
      ? `SELECT component, event, decision, COUNT(*) as count
         FROM events
         WHERE ts >= datetime('now', ? || ' days')
         GROUP BY component, event, decision
         ORDER BY count DESC`
      : `SELECT component, decision, COUNT(*) as count
         FROM events
         WHERE ts >= datetime('now', ? || ' days')
         GROUP BY component, decision
         ORDER BY count DESC`;

    const result = await env.TELEMETRY_DB.prepare(query)
      .bind(`-${safeDays}`)
      .all();

    return jsonResponse(result.results);
  } catch (err) {
    return jsonResponse({ error: 'Database error', detail: err.message }, 500);
  }
}

function validateFeedbackReport(obj) {
  if (!obj || typeof obj !== 'object') return 'body must be a JSON object';
  if (typeof obj.ts !== 'string') return 'ts is required (ISO 8601 string)';
  if (typeof obj.install_id !== 'string') return 'install_id is required';
  if (!obj.items || !Array.isArray(obj.items)) return 'items array is required';
  if (obj.items.length === 0) return 'items must contain at least one finding';
  if (obj.items.length > MAX_FEEDBACK_ITEMS) return `items limited to ${MAX_FEEDBACK_ITEMS}`;

  for (let i = 0; i < obj.items.length; i++) {
    const item = obj.items[i];
    if (!item.category || !VALID_CATEGORIES.includes(item.category)) {
      return `items[${i}].category must be one of: ${VALID_CATEGORIES.join(', ')}`;
    }
    if (typeof item.component !== 'string' || !item.component) {
      return `items[${i}].component is required`;
    }
    if (typeof item.title !== 'string' || !item.title) {
      return `items[${i}].title is required`;
    }
    if (item.severity && !VALID_SEVERITIES.includes(item.severity)) {
      return `items[${i}].severity must be one of: ${VALID_SEVERITIES.join(', ')}`;
    }
  }
  return null;
}

async function handlePostFeedback(request, env) {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (!checkRateLimit(ip)) {
    return jsonResponse({ error: 'Rate limit exceeded' }, 429);
  }

  const contentLength = parseInt(request.headers.get('Content-Length') || '0', 10);
  if (contentLength > MAX_FEEDBACK_BYTES) {
    return jsonResponse({ error: 'Body too large (50KB max)' }, 413);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON' }, 400);
  }

  const validationError = validateFeedbackReport(body);
  if (validationError) {
    return jsonResponse({ error: validationError }, 400);
  }

  try {
    // Insert the report (with narrative and self-critique fields)
    const reportResult = await env.TELEMETRY_DB.prepare(
      `INSERT INTO feedback_reports (ts, install_id, plugin_version, project_type, project_size, overall_grade, model_family, os, review_type, report_json, narrative, self_critique)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(
        body.ts,
        body.install_id,
        body.plugin_version ?? null,
        body.project_type ?? null,
        body.project_size ?? null,
        body.overall_grade ?? null,
        body.model_family ?? null,
        body.os ?? null,
        body.review_type ?? 'manual',
        JSON.stringify(body.report_summary ?? {}),
        (body.narrative ?? '').slice(0, 5000),
        (body.self_critique ?? '').slice(0, 2000)
      )
      .run();

    const reportId = reportResult.meta?.last_row_id;
    if (!reportId) {
      return jsonResponse({ error: 'Failed to create report' }, 500);
    }

    // Batch insert items (description limit raised to 1000, with related_items)
    const itemStmt = env.TELEMETRY_DB.prepare(
      `INSERT INTO feedback_items (report_id, category, component, severity, title, description, related_items)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );
    const itemBatch = body.items.map((item) =>
      itemStmt.bind(
        reportId,
        item.category,
        item.component,
        item.severity ?? null,
        item.title.slice(0, 200),
        (item.description ?? '').slice(0, 1000),
        JSON.stringify(item.related_items ?? [])
      )
    );
    await env.TELEMETRY_DB.batch(itemBatch);

    // Insert component grades if provided
    if (Array.isArray(body.component_grades) && body.component_grades.length > 0) {
      const gradeStmt = env.TELEMETRY_DB.prepare(
        `INSERT INTO feedback_component_grades (report_id, component, grade, notes)
         VALUES (?, ?, ?, ?)`
      );
      const gradeBatch = body.component_grades.map((g) =>
        gradeStmt.bind(
          reportId,
          g.component ?? '',
          g.grade ?? '',
          (g.notes ?? '').slice(0, 500)
        )
      );
      await env.TELEMETRY_DB.batch(gradeBatch);
    }

    return jsonResponse({
      report_id: reportId,
      items_accepted: body.items.length,
      grades_accepted: body.component_grades?.length ?? 0,
    });
  } catch (err) {
    return jsonResponse({ error: 'Database error', detail: err.message }, 500);
  }
}

async function handleGetFeedback(request, env) {
  const url = new URL(request.url);
  const days = parseInt(url.searchParams.get('days') || '90', 10);
  const safeDays = Number.isFinite(days) && days > 0 && days <= 365 ? days : 90;
  const component = url.searchParams.get('component') || null;
  const category = url.searchParams.get('category') || null;

  try {
    // Summary stats
    const [summaryResult, gradeResult] = await env.TELEMETRY_DB.batch([
      env.TELEMETRY_DB.prepare(
        `SELECT COUNT(*) as total_reports,
                COUNT(DISTINCT install_id) as unique_installs
         FROM feedback_reports
         WHERE ts >= datetime('now', ? || ' days')`
      ).bind(`-${safeDays}`),
      env.TELEMETRY_DB.prepare(
        `SELECT overall_grade, COUNT(*) as count
         FROM feedback_reports
         WHERE ts >= datetime('now', ? || ' days') AND overall_grade IS NOT NULL
         GROUP BY overall_grade
         ORDER BY count DESC`
      ).bind(`-${safeDays}`),
    ]);

    // Top issues — optionally filtered by component/category
    let issueQuery = `
      SELECT fi.category, fi.component, fi.severity, fi.title,
             COUNT(*) as report_count,
             COUNT(DISTINCT fr.install_id) as unique_installs
      FROM feedback_items fi
      JOIN feedback_reports fr ON fi.report_id = fr.id
      WHERE fr.ts >= datetime('now', ? || ' days')`;
    const binds = [`-${safeDays}`];

    if (component) {
      issueQuery += ' AND fi.component = ?';
      binds.push(component);
    }
    if (category) {
      issueQuery += ' AND fi.category = ?';
      binds.push(category);
    }

    issueQuery += `
      GROUP BY fi.category, fi.component, fi.title
      ORDER BY report_count DESC
      LIMIT 30`;

    let stmt = env.TELEMETRY_DB.prepare(issueQuery);
    for (const val of binds) {
      stmt = stmt.bind(val);
    }
    const issueResult = await stmt.all();

    // Component breakdown from items
    const componentResult = await env.TELEMETRY_DB.prepare(
      `SELECT fi.component,
              COUNT(DISTINCT fi.report_id) as review_count,
              SUM(CASE WHEN fi.category = 'false_positive' THEN 1 ELSE 0 END) as false_positives,
              SUM(CASE WHEN fi.category = 'bug' THEN 1 ELSE 0 END) as bugs,
              SUM(CASE WHEN fi.category = 'missing_feature' THEN 1 ELSE 0 END) as feature_requests,
              SUM(CASE WHEN fi.category = 'praise' THEN 1 ELSE 0 END) as praise_count
       FROM feedback_items fi
       JOIN feedback_reports fr ON fi.report_id = fr.id
       WHERE fr.ts >= datetime('now', ? || ' days')
       GROUP BY fi.component
       ORDER BY review_count DESC
       LIMIT 30`
    )
      .bind(`-${safeDays}`)
      .all();

    // Component grades from dedicated table
    const gradesResult = await env.TELEMETRY_DB.prepare(
      `SELECT g.component, g.grade, COUNT(*) as count, g.notes
       FROM feedback_component_grades g
       JOIN feedback_reports fr ON g.report_id = fr.id
       WHERE fr.ts >= datetime('now', ? || ' days')
       GROUP BY g.component, g.grade
       ORDER BY count DESC
       LIMIT 50`
    )
      .bind(`-${safeDays}`)
      .all();

    // Recent narratives (the rich reasoning — most recent 5)
    const narrativeResult = await env.TELEMETRY_DB.prepare(
      `SELECT ts, overall_grade, narrative, self_critique, plugin_version, project_type
       FROM feedback_reports
       WHERE ts >= datetime('now', ? || ' days') AND narrative IS NOT NULL AND narrative != ''
       ORDER BY ts DESC
       LIMIT 5`
    )
      .bind(`-${safeDays}`)
      .all();

    return jsonResponse({
      window_days: safeDays,
      summary: summaryResult.results[0] ?? { total_reports: 0, unique_installs: 0 },
      grade_distribution: gradeResult.results,
      top_issues: issueResult.results,
      component_breakdown: componentResult.results,
      component_grades: gradesResult.results,
      recent_narratives: narrativeResult.results,
    });
  } catch (err) {
    return jsonResponse({ error: 'Database error', detail: err.message }, 500);
  }
}

export default {
  async fetch(request, env) {
    const method = request.method.toUpperCase();

    // Handle CORS preflight
    if (method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (path === '/v1/events' && method === 'POST') {
      return handlePostEvents(request, env);
    }

    if (path === '/v1/stats' && method === 'GET') {
      return handleGetStats(request, env);
    }

    if (path === '/v1/hooks' && method === 'GET') {
      return handleGetHooks(request, env);
    }

    if (path === '/v1/feedback' && method === 'POST') {
      return handlePostFeedback(request, env);
    }

    if (path === '/v1/feedback' && method === 'GET') {
      return handleGetFeedback(request, env);
    }

    return jsonResponse({ error: 'Not found' }, 404);
  },
};
