(function () {
  'use strict';

  var root = document.documentElement;
  var systemDark = window.matchMedia('(prefers-color-scheme: dark)');
  var flashTimer;

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
    applyTheme(root.dataset.themeMode || 'auto');
    tick();
    setInterval(tick, 1000);
  });
})();
