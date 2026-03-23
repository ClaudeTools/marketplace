#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');
const os = require('os');

// --- Utility functions ---

function getMeshRoot() {
  try {
    // Safe: hardcoded command, no user input — execSync is appropriate here
    const gitCommonDir = execSync('git rev-parse --path-format=absolute --git-common-dir', {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
    // gitCommonDir is e.g. /repo/.git — mesh root is /repo/.claude/mesh/
    const repoRoot = path.dirname(gitCommonDir);
    return path.join(repoRoot, '.claude', 'mesh');
  } catch {
    // Fallback: use CWD
    return path.join(process.cwd(), '.claude', 'mesh');
  }
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function atomicWrite(filePath, data) {
  ensureDir(path.dirname(filePath));
  const tmp = filePath + '.tmp.' + crypto.randomBytes(4).toString('hex');
  fs.writeFileSync(tmp, typeof data === 'string' ? data : JSON.stringify(data, null, 2));
  fs.renameSync(tmp, filePath);
}

function readJSON(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const result = {};
  let i = 0;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        result[key] = true;
        i++;
      } else {
        result[key] = next;
        i += 2;
      }
    } else {
      i++;
    }
  }
  return result;
}

function isPidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function hashPath(filePath) {
  return crypto.createHash('sha256').update(filePath).digest('hex').slice(0, 16);
}

function now() {
  return new Date().toISOString();
}

function fail(msg) {
  process.stderr.write(msg + '\n');
  process.exit(1);
}

// --- Paths ---

const MESH = getMeshRoot();
const AGENTS_DIR = path.join(MESH, 'agents');
const INBOX_DIR = path.join(MESH, 'inbox');
const LOCKS_DIR = path.join(MESH, 'locks');
const CONTEXT_FILE = path.join(MESH, 'context', 'shared.jsonl');

// --- Commands ---

function cmdRegister(opts) {
  const { id, name, worktree, branch, pid, task } = opts;
  if (!id || !name || !worktree || !branch || !pid) {
    fail('Usage: register --id ID --name NAME --worktree PATH --branch BRANCH --pid PID [--task TEXT]');
  }
  const agent = {
    id,
    name,
    worktree,
    branch,
    task: task || '',
    pid: parseInt(pid, 10),
    files_active: [],
    registered_at: now(),
    last_heartbeat: now(),
    status: 'active',
  };
  atomicWrite(path.join(AGENTS_DIR, id + '.json'), agent);
  // Ensure inbox directory for this agent
  ensureDir(path.join(INBOX_DIR, name));
  console.log(`Registered agent "${name}" (${id})`);
}

function cmdDeregister(opts) {
  const { id } = opts;
  if (!id) fail('Usage: deregister --id ID');
  const agentFile = path.join(AGENTS_DIR, id + '.json');
  if (fs.existsSync(agentFile)) {
    fs.unlinkSync(agentFile);
    console.log(`Deregistered agent ${id}`);
  } else {
    fail(`Agent ${id} not found`);
  }
}

function cmdHeartbeat(opts) {
  const { id } = opts;
  if (!id) fail('Usage: heartbeat --id ID');
  const agentFile = path.join(AGENTS_DIR, id + '.json');
  const agent = readJSON(agentFile);
  if (!agent) fail(`Agent ${id} not found`);
  agent.last_heartbeat = now();
  atomicWrite(agentFile, agent);
  console.log(`Heartbeat updated for ${id}`);
}

function cmdList(opts) {
  const { exclude } = opts;
  const brief = opts.brief === true;
  ensureDir(AGENTS_DIR);
  const files = fs.readdirSync(AGENTS_DIR).filter(f => f.endsWith('.json'));
  const agents = [];
  const staleThreshold = 30 * 60 * 1000; // 30 minutes — hooks are ephemeral, so PID may not survive; rely on heartbeats

  for (const file of files) {
    const agent = readJSON(path.join(AGENTS_DIR, file));
    if (!agent) continue;
    if (exclude && agent.id === exclude) continue;

    // Stale detection: dead PID + heartbeat > 5 min
    const heartbeatAge = Date.now() - new Date(agent.last_heartbeat).getTime();
    if (!isPidAlive(agent.pid) && heartbeatAge > staleThreshold) {
      // Remove stale agent
      try { fs.unlinkSync(path.join(AGENTS_DIR, file)); } catch {}
      continue;
    }

    agents.push(agent);
  }

  if (agents.length === 0) {
    console.log('No active agents');
    return;
  }

  if (brief) {
    for (const a of agents) {
      console.log(`${a.name} (${a.id}) — ${a.branch}${a.task ? ' — ' + a.task : ''}`);
    }
  } else {
    console.log(JSON.stringify(agents, null, 2));
  }
}

function cmdSend(opts) {
  const { to, broadcast, message, type, from } = opts;
  if (!message) fail('Usage: send --to NAME --message TEXT [--type TYPE] [--from NAME]');
  if (!to && broadcast !== true) fail('Must specify --to NAME or --broadcast');

  const msg = {
    id: `msg-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`,
    from: from || 'unknown',
    to: broadcast ? '*' : to,
    timestamp: now(),
    type: type || 'info',
    content: message,
    read: false,
  };

  if (broadcast) {
    const dir = path.join(INBOX_DIR, 'broadcast');
    ensureDir(dir);
    atomicWrite(path.join(dir, msg.id + '.json'), msg);
    console.log(`Broadcast message sent (${msg.id})`);
  } else {
    const dir = path.join(INBOX_DIR, to);
    ensureDir(dir);
    atomicWrite(path.join(dir, msg.id + '.json'), msg);
    console.log(`Message sent to "${to}" (${msg.id})`);
  }
}

function cmdInbox(opts) {
  const { id, ack } = opts;
  if (!id) fail('Usage: inbox --id ID [--ack]');

  // Find agent name from id
  const agentFile = path.join(AGENTS_DIR, id + '.json');
  const agent = readJSON(agentFile);
  if (!agent) fail(`Agent ${id} not found`);

  const messages = [];
  const dirs = [
    path.join(INBOX_DIR, agent.name),
    path.join(INBOX_DIR, 'broadcast'),
  ];

  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.json'));
    for (const file of files) {
      const filePath = path.join(dir, file);
      const msg = readJSON(filePath);
      if (msg) {
        msg._path = filePath;
        messages.push(msg);
      }
    }
  }

  messages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

  if (messages.length === 0) {
    console.log('No messages');
    return;
  }

  for (const msg of messages) {
    console.log(`[${msg.timestamp}] ${msg.from} -> ${msg.to} (${msg.type}): ${msg.content}`);
  }

  if (ack === true) {
    for (const msg of messages) {
      try { fs.unlinkSync(msg._path); } catch {}
    }
    console.log(`Acknowledged ${messages.length} message(s)`);
  }
}

function cmdLock(opts) {
  const { file, id, reason } = opts;
  if (!file || !id) fail('Usage: lock --file PATH --id ID [--reason TEXT]');

  // Look up agent name
  const agentFile = path.join(AGENTS_DIR, id + '.json');
  const agent = readJSON(agentFile);
  const agentName = agent ? agent.name : id;

  const lockFile = path.join(LOCKS_DIR, hashPath(file) + '.json');
  ensureDir(LOCKS_DIR);

  // Check for existing lock
  const existing = readJSON(lockFile);
  if (existing && existing.agent_id !== id) {
    fail(`File "${file}" is already locked by ${existing.agent_name} (${existing.agent_id})`);
  }

  const lock = {
    file,
    agent_id: id,
    agent_name: agentName,
    reason: reason || '',
    locked_at: now(),
  };
  atomicWrite(lockFile, lock);
  console.log(`Locked "${file}"`);
}

function cmdUnlock(opts) {
  const { file, id } = opts;
  if (!file || !id) fail('Usage: unlock --file PATH --id ID');

  const lockFile = path.join(LOCKS_DIR, hashPath(file) + '.json');
  const existing = readJSON(lockFile);
  if (!existing) {
    fail(`File "${file}" is not locked`);
  }
  if (existing.agent_id !== id) {
    fail(`File "${file}" is locked by ${existing.agent_name} (${existing.agent_id}), not you`);
  }
  fs.unlinkSync(lockFile);
  console.log(`Unlocked "${file}"`);
}

function cmdLocks() {
  ensureDir(LOCKS_DIR);
  const files = fs.readdirSync(LOCKS_DIR).filter(f => f.endsWith('.json'));
  if (files.length === 0) {
    console.log('No active locks');
    return;
  }
  for (const file of files) {
    const lock = readJSON(path.join(LOCKS_DIR, file));
    if (!lock) continue;
    console.log(`${lock.file} — locked by ${lock.agent_name} (${lock.agent_id})${lock.reason ? ' — ' + lock.reason : ''}`);
  }
}

function cmdContext(opts) {
  const { set, get, list } = opts;

  if (set) {
    // --set KEY VALUE: the key is `set` value, value is next positional
    // Re-parse to get positional args after --set
    const argv = process.argv.slice(2);
    const setIdx = argv.indexOf('--set');
    if (setIdx === -1 || setIdx + 2 >= argv.length) {
      fail('Usage: context --set KEY VALUE');
    }
    const key = argv[setIdx + 1];
    const value = argv[setIdx + 2];

    ensureDir(path.dirname(CONTEXT_FILE));
    const entry = JSON.stringify({
      key,
      value,
      timestamp: now(),
      author: opts.from || os.userInfo().username,
    });
    fs.appendFileSync(CONTEXT_FILE, entry + '\n');
    console.log(`Set context "${key}"`);
    return;
  }

  if (get) {
    const key = typeof get === 'string' ? get : null;
    if (!key) fail('Usage: context --get KEY');

    if (!fs.existsSync(CONTEXT_FILE)) {
      fail(`Key "${key}" not found`);
    }
    const lines = fs.readFileSync(CONTEXT_FILE, 'utf8').trim().split('\n').filter(Boolean);
    let found = null;
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.key === key) found = entry;
      } catch {}
    }
    if (!found) fail(`Key "${key}" not found`);
    console.log(`${found.key} = ${found.value} (set ${found.timestamp} by ${found.author})`);
    return;
  }

  if (list === true) {
    if (!fs.existsSync(CONTEXT_FILE)) {
      console.log('No shared context');
      return;
    }
    const lines = fs.readFileSync(CONTEXT_FILE, 'utf8').trim().split('\n').filter(Boolean);
    const latest = new Map();
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        latest.set(entry.key, entry);
      } catch {}
    }
    if (latest.size === 0) {
      console.log('No shared context');
      return;
    }
    for (const [key, entry] of latest) {
      console.log(`${key} = ${entry.value} (set ${entry.timestamp} by ${entry.author})`);
    }
    return;
  }

  fail('Usage: context --set KEY VALUE | context --get KEY | context --list');
}

function cmdTrackFile(opts) {
  const { id, file } = opts;
  if (!id || !file) fail('Usage: track-file --id ID --file PATH');

  const agentFile = path.join(AGENTS_DIR, id + '.json');
  const agent = readJSON(agentFile);
  if (!agent) fail(`Agent ${id} not found`);

  if (!agent.files_active.includes(file)) {
    agent.files_active.push(file);
    atomicWrite(agentFile, agent);
  }
  console.log(`Tracking "${file}" for agent ${agent.name}`);
}

function cmdWho(opts) {
  const { file } = opts;
  if (!file) fail('Usage: who --file PATH');

  ensureDir(AGENTS_DIR);
  const agentFiles = fs.readdirSync(AGENTS_DIR).filter(f => f.endsWith('.json'));
  const results = [];

  for (const af of agentFiles) {
    const agent = readJSON(path.join(AGENTS_DIR, af));
    if (!agent) continue;
    if (agent.files_active && agent.files_active.includes(file)) {
      results.push(agent);
    }
  }

  // Also check locks
  const lockFile = path.join(LOCKS_DIR, hashPath(file) + '.json');
  const lock = readJSON(lockFile);

  if (results.length === 0 && !lock) {
    console.log(`No agents working on "${file}"`);
    return;
  }

  for (const a of results) {
    console.log(`${a.name} (${a.id}) — tracking`);
  }
  if (lock) {
    console.log(`${lock.agent_name} (${lock.agent_id}) — locked${lock.reason ? ' — ' + lock.reason : ''}`);
  }
}

function cmdHelp() {
  const helpText = `agent-mesh — Cross-session agent coordination CLI

Usage: node cli.js <command> [options]

Commands:
  register    --id ID --name NAME --worktree PATH --branch BRANCH --pid PID [--task TEXT]
              Register an agent session

  deregister  --id ID
              Remove an agent registration

  heartbeat   --id ID
              Update agent heartbeat timestamp

  list        [--exclude ID] [--brief]
              List active agents (auto-removes stale ones)

  send        --to NAME --message TEXT [--type info|alert|request|decision] [--from NAME]
  send        --broadcast --message TEXT [--from NAME]
              Send a message to an agent or broadcast to all

  inbox       --id ID [--ack]
              Read messages for an agent (--ack to delete after reading)

  lock        --file PATH --id ID [--reason TEXT]
              Acquire an advisory lock on a file

  unlock      --file PATH --id ID
              Release a file lock

  locks       List all active locks

  context     --set KEY VALUE
              Set a shared context value

  context     --get KEY
              Get a shared context value

  context     --list
              List all shared context values

  track-file  --id ID --file PATH
              Track a file as actively being worked on by an agent

  who         --file PATH
              Show which agents are working on a file

  help        Show this help message`;
  process.stdout.write(helpText + '\n');
}

// --- Main ---

const args = process.argv.slice(2);
const command = args[0];
const opts = parseArgs(args.slice(1));

switch (command) {
  case 'register':    cmdRegister(opts); break;
  case 'deregister':  cmdDeregister(opts); break;
  case 'heartbeat':   cmdHeartbeat(opts); break;
  case 'list':        cmdList(opts); break;
  case 'send':        cmdSend(opts); break;
  case 'inbox':       cmdInbox(opts); break;
  case 'lock':        cmdLock(opts); break;
  case 'unlock':      cmdUnlock(opts); break;
  case 'locks':       cmdLocks(); break;
  case 'context':     cmdContext(opts); break;
  case 'track-file':  cmdTrackFile(opts); break;
  case 'who':         cmdWho(opts); break;
  case 'help':
  case '--help':
  case '-h':          cmdHelp(); break;
  case undefined:     cmdHelp(); break;
  default:            fail(`Unknown command: ${command}. Run "help" for usage.`);
}
