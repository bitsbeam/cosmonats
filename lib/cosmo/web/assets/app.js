(function () {
  'use strict';

  var root = document.documentElement;
  var systemDark = window.matchMedia('(prefers-color-scheme: dark)');
  var flashTimer;
  var BACKOFF_LIMIT = 60000;

  if (window.htmx) htmx.config.timeout = 20000;

  function isPoller(el) {
    return !!(el && el.dataset && el.dataset.poll !== undefined);
  }

  function pollDelay(el) {
    var base = (parseFloat(el.dataset.poll) || 5) * 1000;
    return Math.min(base * Math.pow(2, el.cosmoFailures || 0), Math.max(base, BACKOFF_LIMIT));
  }

  function poll(el) {
    if (!el.isConnected) return;
    if (document.hidden) {
      el.cosmoHeld = true;
      return;
    }
    htmx.trigger(el, 'cosmo:poll');
  }

  function schedule(el) {
    clearTimeout(el.cosmoTimer);
    if (el.isConnected) el.cosmoTimer = setTimeout(function () { poll(el); }, pollDelay(el));
  }

  function markOnline(online) {
    document.body.classList.toggle('offline', !online);
    var label = document.querySelector('.live-label');
    if (label) label.textContent = online ? 'live' : 'offline';
  }

  function settled(el, failed) {
    if (!el.cosmoPolling) return;
    el.cosmoPolling = false;
    el.cosmoFailures = failed ? (el.cosmoFailures || 0) + 1 : 0;
    markOnline(!failed);
    schedule(el);
  }

  document.addEventListener('htmx:beforeRequest', function (event) {
    if (isPoller(event.detail.elt)) event.detail.elt.cosmoPolling = true;
  });

  document.addEventListener('htmx:afterRequest', function (event) {
    if (isPoller(event.detail.elt)) settled(event.detail.elt, !event.detail.successful);
  });

  ['htmx:sendError', 'htmx:timeout'].forEach(function (name) {
    document.addEventListener(name, function (event) {
      if (isPoller(event.detail.elt)) settled(event.detail.elt, true);
    });
  });

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) return;
    document.querySelectorAll('[data-poll]').forEach(function (el) {
      if (!el.cosmoHeld) return;
      el.cosmoHeld = false;
      poll(el);
    });
  });

  if (window.htmx) {
    htmx.onLoad(function (content) {
      var pollers = Array.prototype.slice.call(content.querySelectorAll('[data-poll]'));
      if (isPoller(content)) pollers.push(content);
      pollers.forEach(function (el) {
        if (!/\bload\b/.test(el.getAttribute('hx-trigger') || '')) schedule(el);
      });
    });
  }

  function store(key, value) {
    try { localStorage.setItem(key, value); } catch (e) {}
  }

  function applyTheme(mode) {
    root.dataset.themeMode = mode;
    root.dataset.theme = mode === 'auto' ? (systemDark.matches ? 'dark' : 'light') : mode;
    document.querySelectorAll('[data-theme-set]').forEach(function (button) {
      var on = button.dataset.themeSet === mode;
      button.classList.toggle('on', on);
      button.setAttribute('aria-pressed', on);
    });
  }

  systemDark.addEventListener('change', function () {
    if (root.dataset.themeMode === 'auto') applyTheme('auto');
  });

  var actions = {
    theme: function (el) {
      store('cosmo-theme', el.dataset.themeSet);
      applyTheme(el.dataset.themeSet);
    },
    'open-menu': function () { document.body.classList.add('menu-open'); },
    'close-menu': function () { document.body.classList.remove('menu-open'); }
  };

  function tick() {
    var clock = document.getElementById('clock');
    if (clock) clock.textContent = ' · ' + new Date().toLocaleTimeString('en-GB');
  }

  function hideFlash() {
    var flash = document.getElementById('flash');
    if (!flash || !flash.textContent.trim()) return;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(function () { flash.textContent = ''; }, 2400);
  }

  document.addEventListener('click', function (event) {
    var el = event.target.closest('[data-action]');
    if (el && actions[el.dataset.action]) actions[el.dataset.action](el);
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') document.body.classList.remove('menu-open');
  });

  window.addEventListener('resize', function () {
    if (window.innerWidth > 900) document.body.classList.remove('menu-open');
  });

  document.addEventListener('htmx:beforeSwap', function (event) {
    event.detail.target.cosmoScroll = Array.prototype.map.call(
      event.detail.target.querySelectorAll('.scroll'), function (el) { return el.scrollLeft; }
    );
  });

  document.addEventListener('htmx:afterSettle', function (event) {
    var saved = event.detail.target.cosmoScroll;
    if (saved) {
      event.detail.target.querySelectorAll('.scroll').forEach(function (el, i) { el.scrollLeft = saved[i] || 0; });
    }
    hideFlash();
  });

  document.addEventListener('DOMContentLoaded', function () {
    var reload = document.querySelector('[data-reload]');
    if (reload) {
      markOnline(false);
      setTimeout(function () { location.reload(); }, (parseFloat(reload.dataset.reload) || 10) * 1000);
    }

    applyTheme(root.dataset.themeMode || 'auto');
    tick();
    setInterval(tick, 1000);
  });
})();
