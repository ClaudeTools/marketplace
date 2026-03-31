#!/usr/bin/env node
'use strict';
// Visual companion server — HTTP + WebSocket, zero external dependencies
// Serves HTML content files, broadcasts reload on file changes, captures click events.

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');

// ─── Config from env ──────────────────────────────────────────────────────────
const BRAINSTORM_DIR = process.env.BRAINSTORM_DIR || path.join(os.tmpdir(), 'claudetools-design-default');
const CONTENT_DIR    = path.join(BRAINSTORM_DIR, 'content');
const STATE_DIR      = path.join(BRAINSTORM_DIR, 'state');
const HOST           = process.env.BRAINSTORM_HOST     || '127.0.0.1';
const URL_HOST       = process.env.BRAINSTORM_URL_HOST || HOST;
const OWNER_PID      = parseInt(process.env.BRAINSTORM_OWNER_PID || '0', 10);

const PORT_MIN       = 49152;
const PORT_MAX       = 65535;
const IDLE_TIMEOUT   = 30 * 60 * 1000; // 30 minutes
const OWNER_CHECK_MS = 60 * 1000;       // 60 seconds

// ─── State ────────────────────────────────────────────────────────────────────
let currentScreen  = null;   // path to newest .html file
let frameTemplate  = null;   // cached frame-template.html contents
let helperJs       = null;   // cached helper.js contents
const clients      = new Set();
let idleTimer      = null;
let port           = 0;

// ─── Utilities ────────────────────────────────────────────────────────────────

function randomPort() {
  return PORT_MIN + Math.floor(Math.random() * (PORT_MAX - PORT_MIN + 1));
}

function loadAsset(name) {
  const p = path.join(__dirname, name);
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function ensureDirs() {
  fs.mkdirSync(CONTENT_DIR, { recursive: true });
  fs.mkdirSync(STATE_DIR,   { recursive: true });
}

function resetIdleTimer() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => shutdown('idle-timeout'), IDLE_TIMEOUT);
}

function isFullDocument(html) {
  const trimmed = html.trimStart().toLowerCase();
  return trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');
}

function wrapFragment(html) {
  const tmpl = frameTemplate || '<html><body><!-- CONTENT --><script src="/helper.js"></script></body></html>';
  return tmpl.replace('<!-- CONTENT -->', html);
}

function buildResponse(htmlPath) {
  let src;
  try { src = fs.readFileSync(htmlPath, 'utf8'); } catch { return '<html><body><p>Loading...</p></body></html>'; }

  let doc = isFullDocument(src) ? src : wrapFragment(src);

  // Inject helper.js before </body> if not already present
  if (!doc.includes('/helper.js')) {
    doc = doc.replace(/<\/body>/i, '<script src="/helper.js"></script>\n</body>');
  }
  return doc;
}

// ─── Newest file detection ────────────────────────────────────────────────────

function findNewestHtml() {
  let files;
  try { files = fs.readdirSync(CONTENT_DIR); } catch { return null; }
  const htmlFiles = files
    .filter(f => f.endsWith('.html'))
    .map(f => ({ name: f, mtime: fs.statSync(path.join(CONTENT_DIR, f)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  return htmlFiles.length ? path.join(CONTENT_DIR, htmlFiles[0].name) : null;
}

// ─── WebSocket RFC 6455 implementation ───────────────────────────────────────

function wsHandshake(req, socket) {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const accept = crypto
    .createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n` +
    '\r\n'
  );
}

function wsEncode(data) {
  const payload = Buffer.from(typeof data === 'string' ? data : JSON.stringify(data), 'utf8');
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // FIN + text opcode
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function wsDecode(buf) {
  if (buf.length < 2) return null;
  const fin  = (buf[0] & 0x80) !== 0;
  const opcode = buf[0] & 0x0f;
  const masked = (buf[1] & 0x80) !== 0;
  let lenByte = buf[1] & 0x7f;
  let offset = 2;
  let payloadLen;

  if (lenByte < 126) {
    payloadLen = lenByte;
  } else if (lenByte === 126) {
    if (buf.length < 4) return null;
    payloadLen = buf.readUInt16BE(2);
    offset = 4;
  } else {
    if (buf.length < 10) return null;
    payloadLen = Number(buf.readBigUInt64BE(2));
    offset = 10;
  }

  if (masked) {
    if (buf.length < offset + 4 + payloadLen) return null;
    const mask = buf.slice(offset, offset + 4);
    offset += 4;
    const payload = Buffer.alloc(payloadLen);
    for (let i = 0; i < payloadLen; i++) {
      payload[i] = buf[offset + i] ^ mask[i % 4];
    }
    return { fin, opcode, payload: payload.toString('utf8') };
  } else {
    if (buf.length < offset + payloadLen) return null;
    return { fin, opcode, payload: buf.slice(offset, offset + payloadLen).toString('utf8') };
  }
}

function wsSendAll(msg) {
  const frame = wsEncode(msg);
  for (const sock of clients) {
    try { sock.write(frame); } catch { clients.delete(sock); }
  }
}

// ─── Events file ─────────────────────────────────────────────────────────────

function clearEvents() {
  try { fs.writeFileSync(path.join(STATE_DIR, 'events'), ''); } catch {}
}

function appendEvent(obj) {
  const line = JSON.stringify(obj) + '\n';
  try { fs.appendFileSync(path.join(STATE_DIR, 'events'), line); } catch {}
}

// ─── File watcher ─────────────────────────────────────────────────────────────

let watchDebounce = null;

function onContentChange(eventType, filename) {
  if (filename && !filename.endsWith('.html')) return;
  if (watchDebounce) clearTimeout(watchDebounce);
  watchDebounce = setTimeout(() => {
    const newest = findNewestHtml();
    if (!newest) return;
    const changed = newest !== currentScreen;
    currentScreen = newest;
    if (changed) {
      clearEvents();
    }
    wsSendAll(JSON.stringify({ type: 'reload' }));
    resetIdleTimer();
  }, 100);
}

// ─── HTTP handlers ───────────────────────────────────────────────────────────

function serveRequest(req, res) {
  resetIdleTimer();

  if (req.url === '/helper.js') {
    const src = helperJs || '// helper.js not found';
    res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8' });
    res.end(src);
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, port, screen: currentScreen }));
    return;
  }

  // Serve current screen (all paths → same content)
  const html = currentScreen
    ? buildResponse(currentScreen)
    : wrapFragment('<div style="display:flex;align-items:center;justify-content:center;min-height:60vh"><p class="subtitle">Waiting for content...</p></div>');

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(html);
}

// ─── Shutdown ─────────────────────────────────────────────────────────────────

function shutdown(reason) {
  const stopped = { type: 'server-stopped', reason, pid: process.pid };
  try { fs.writeFileSync(path.join(STATE_DIR, 'server-stopped'), JSON.stringify(stopped) + '\n'); } catch {}
  try { fs.unlinkSync(path.join(STATE_DIR, 'server.pid')); } catch {}
  process.exit(0);
}

// ─── Owner PID check ─────────────────────────────────────────────────────────

function checkOwner() {
  if (!OWNER_PID) return;
  try {
    process.kill(OWNER_PID, 0); // signal 0 = check existence only
  } catch {
    shutdown('owner-exited');
  }
}

// ─── Port binding with retry ──────────────────────────────────────────────────

function tryBind(server, attempt, cb) {
  const p = randomPort();
  server.listen(p, HOST, () => { cb(null, p); });
  server.once('error', (err) => {
    if (err.code === 'EADDRINUSE' && attempt < 20) {
      server.removeAllListeners('error');
      server.removeAllListeners('listening');
      tryBind(server, attempt + 1, cb);
    } else {
      cb(err);
    }
  });
}

// ─── Main ─────────────────────────────────────────────────────────────────────

function main() {
  ensureDirs();
  frameTemplate = loadAsset('frame-template.html');
  helperJs      = loadAsset('helper.js');

  currentScreen = findNewestHtml();

  const server = http.createServer(serveRequest);

  // WebSocket upgrade
  server.on('upgrade', (req, socket, head) => {
    if (req.headers.upgrade.toLowerCase() !== 'websocket') {
      socket.destroy();
      return;
    }

    wsHandshake(req, socket);
    clients.add(socket);
    resetIdleTimer();

    let buffer = Buffer.alloc(0);

    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      const frame = wsDecode(buffer);
      if (!frame) return;
      buffer = Buffer.alloc(0); // consume (simple single-frame messages)

      if (frame.opcode === 8) { // close
        clients.delete(socket);
        socket.destroy();
        return;
      }

      if (frame.opcode === 9) { // ping → pong
        const pong = Buffer.alloc(2);
        pong[0] = 0x8a;
        pong[1] = 0;
        socket.write(pong);
        return;
      }

      if (frame.opcode === 1) { // text
        let msg;
        try { msg = JSON.parse(frame.payload); } catch { return; }
        if (msg && msg.type === 'click') {
          appendEvent({ ...msg, serverTime: Date.now() });
          resetIdleTimer();
        }
      }
    });

    socket.on('close', () => clients.delete(socket));
    socket.on('error', () => clients.delete(socket));
  });

  tryBind(server, 0, (err, p) => {
    if (err) { process.stderr.write('server bind failed: ' + err.message + '\n'); process.exit(1); }
    port = p;

    const url = `http://${URL_HOST}:${port}`;

    // Write PID
    try { fs.writeFileSync(path.join(STATE_DIR, 'server.pid'), String(process.pid)); } catch {}

    // Write server-info (agent reconnects using this)
    const info = { type: 'server-started', port, url, screen_dir: CONTENT_DIR, state_dir: STATE_DIR, pid: process.pid };
    try { fs.writeFileSync(path.join(STATE_DIR, 'server-info'), JSON.stringify(info) + '\n'); } catch {}

    // Emit startup JSON to stdout
    process.stdout.write(JSON.stringify(info) + '\n');

    // Start file watcher
    try {
      fs.watch(CONTENT_DIR, { persistent: false }, onContentChange);
    } catch (e) {
      process.stderr.write('watch failed: ' + e.message + '\n');
    }

    // Owner PID check
    if (OWNER_PID) {
      setInterval(checkOwner, OWNER_CHECK_MS).unref();
    }

    // Start idle timer
    resetIdleTimer();
  });

  process.on('SIGTERM', () => shutdown('sigterm'));
  process.on('SIGINT',  () => shutdown('sigint'));
}

main();
