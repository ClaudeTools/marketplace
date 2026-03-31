// helper.js — browser-side event handler for visual companion
// Loaded by the frame template. Connects to the WebSocket server,
// captures [data-choice] clicks, manages selection UI, and listens for reload.

(function () {
  'use strict';

  // WebSocket connection
  const wsUrl = 'ws://' + location.host;
  let ws = null;
  let queue = [];
  let connected = false;

  function connect() {
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      scheduleReconnect();
      return;
    }

    ws.addEventListener('open', function () {
      connected = true;
      setStatus('connected');
      // Flush queued events
      queue.forEach(function (msg) { safeSend(msg); });
      queue = [];
    });

    ws.addEventListener('message', function (evt) {
      let msg;
      try { msg = JSON.parse(evt.data); } catch { return; }
      if (msg && msg.type === 'reload') {
        location.reload();
      }
    });

    ws.addEventListener('close', function () {
      connected = false;
      setStatus('disconnected');
      scheduleReconnect();
    });

    ws.addEventListener('error', function () {
      connected = false;
      setStatus('disconnected');
    });
  }

  function scheduleReconnect() {
    setTimeout(connect, 2000);
  }

  function safeSend(msg) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(msg));
    } else {
      queue.push(msg);
    }
  }

  // ─── Status indicator ────────────────────────────────────────────────────

  function setStatus(state) {
    const dot = document.getElementById('ws-status-dot');
    if (!dot) return;
    dot.className = 'ws-dot ws-dot--' + state;
    dot.title = state === 'connected' ? 'Live' : 'Reconnecting...';
  }

  // ─── Indicator bar ────────────────────────────────────────────────────────

  function updateIndicator(text) {
    const el = document.getElementById('indicator-text');
    if (el) el.textContent = text;
  }

  // ─── Selection helpers ───────────────────────────────────────────────────

  function getMultiselectContainer(el) {
    let node = el.parentElement;
    while (node) {
      if (node.hasAttribute('data-multiselect')) return node;
      node = node.parentElement;
    }
    return null;
  }

  function toggleSelect(el) {
    const multiContainer = getMultiselectContainer(el);
    if (multiContainer) {
      // Multi-select: toggle this item
      el.classList.toggle('selected');
    } else {
      // Single-select: deselect siblings, select this
      const parent = el.parentElement;
      if (parent) {
        parent.querySelectorAll('[data-choice]').forEach(function (sibling) {
          sibling.classList.remove('selected');
        });
      }
      el.classList.add('selected');
    }

    // Update indicator bar
    const container = multiContainer || el.parentElement;
    if (container) {
      const selected = Array.from(container.querySelectorAll('[data-choice].selected'));
      if (selected.length === 0) {
        updateIndicator('Click an option, then return to terminal');
      } else {
        const labels = selected.map(function (s) {
          return s.getAttribute('data-choice') || s.textContent.trim().slice(0, 30);
        });
        updateIndicator('Selected: ' + labels.join(', ') + ' — return to terminal to confirm');
      }
    }
  }

  // ─── Click listener ───────────────────────────────────────────────────────

  document.addEventListener('click', function (evt) {
    const target = evt.target.closest('[data-choice]');
    if (!target) return;

    toggleSelect(target);

    const event = {
      type:      'click',
      choice:    target.getAttribute('data-choice'),
      text:      target.textContent.trim().slice(0, 200),
      id:        target.id || null,
      timestamp: Date.now()
    };

    safeSend(event);
  });

  // ─── Init ─────────────────────────────────────────────────────────────────

  connect();
  updateIndicator('Click an option, then return to terminal');

  // Expose for inline onclick usage if needed
  window.toggleSelect = toggleSelect;
})();
