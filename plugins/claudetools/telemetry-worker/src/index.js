const MAX_LINES = 100;
const MAX_BODY_BYTES = 1_000_000; // 1MB
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 10;

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

  try {
    const result = await env.TELEMETRY_DB.prepare(
      `SELECT component, decision, COUNT(*) as count
       FROM events
       WHERE ts >= datetime('now', ? || ' days')
       GROUP BY component, decision
       ORDER BY count DESC`
    )
      .bind(`-${safeDays}`)
      .all();

    return jsonResponse(result.results);
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

    return jsonResponse({ error: 'Not found' }, 404);
  },
};
