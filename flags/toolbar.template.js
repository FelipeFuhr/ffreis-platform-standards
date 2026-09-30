(function (global, doc) {
  'use strict';

  // ---------------------------------------------------------------------
  // SYNCHRONOUS BOOT — read this before moving anything.
  //
  // Resolution runs at SCRIPT-PARSE TIME, at the bottom of this file, NOT
  // inside a DOMContentLoaded listener. That is load-bearing, not style:
  // sibling scripts register their own DOMContentLoaded listeners and read
  // flag values during their boot. A listener registered here fires in
  // registration order, so any override applied inside one lands AFTER those
  // readers have already used the un-overridden value — the override then has
  // no observable effect, and the failure is silent. The shape of that bug in
  // the wild: a page renders signed-out after a confirmed login, with zero
  // /api calls in the network panel.
  //
  // Only DOM MOUNTING (which needs document.body) may be deferred; it never
  // changes a resolved value.
  // ---------------------------------------------------------------------

  var KEY_PREFIX = 'dev.route.';
  var QUERY_PREFIX = 'flag.';

  function storageKey(flag) {
    return KEY_PREFIX + flag.category + '.' + flag.name;
  }

  function hostMatches(host, rule) {
    if (rule.charAt(0) === '*') { return host.slice(-(rule.length - 1)) === rule.slice(1); }
    return host === rule;
  }

  function isDevHost(host) {
    if (!host) { return true; }               // file:// — a local checkout
    for (var i = 0; i < DEV_HOSTS.length; i++) {
      if (hostMatches(host, DEV_HOSTS[i])) { return true; }
    }
    return false;
  }

  function lsGet(key) {
    try { return global.localStorage.getItem(key); } catch (e) { return null; }
  }

  function lsSet(key, value) {
    try {
      if (value === null) { global.localStorage.removeItem(key); }
      else { global.localStorage.setItem(key, value); }
    } catch (e) { /* private mode / disabled storage — defaults still apply */ }
  }

  function declaredDefault(flag) {
    return typeof flag.default === 'boolean' ? String(flag.default) : String(flag.default);
  }

  function accepts(flag, value) {
    if (flag.effect === 'route') {
      return (flag.options || []).indexOf(value) !== -1;
    }
    return value === 'true' || value === 'false';
  }

  // A query-string override is a one-shot convenience: ?flag.api.x=y. It is
  // persisted so a reload keeps it, and it is applied HERE, synchronously,
  // for exactly the reason in the banner above.
  function ingestQueryOverrides(flags, search) {
    if (!search || search.length < 2) { return; }
    var parts = search.slice(1).split('&');
    for (var i = 0; i < parts.length; i++) {
      var eq = parts[i].indexOf('=');
      if (eq < 0) { continue; }
      var rawKey = decodeURIComponent(parts[i].slice(0, eq).replace(/\+/g, ' '));
      if (rawKey.indexOf(QUERY_PREFIX) !== 0) { continue; }
      var target = rawKey.slice(QUERY_PREFIX.length);
      var rawValue = decodeURIComponent(parts[i].slice(eq + 1).replace(/\+/g, ' '));
      for (var f = 0; f < flags.length; f++) {
        var flag = flags[f];
        if (target !== flag.name && target !== flag.category + '.' + flag.name) { continue; }
        if (accepts(flag, rawValue)) { lsSet(storageKey(flag), rawValue); }
      }
    }
  }

  // The whole resolution rule, in one place: on a production host the stored
  // override is ignored outright, so a dial left set months ago in a dev
  // session can never re-route a real user (and can never bill real inference).
  function resolveOne(flag, devHost) {
    if (!devHost || flag.binding === 'compile') { return declaredDefault(flag); }
    var stored = lsGet(storageKey(flag));
    if (stored !== null && stored !== '' && accepts(flag, stored)) { return stored; }
    return declaredDefault(flag);
  }

  function buildApi(registry, devHost) {
    var flags = registry.flags || [];
    var byName = {};
    var values = {};
    for (var i = 0; i < flags.length; i++) {
      byName[flags[i].name] = flags[i];
      values[flags[i].name] = resolveOne(flags[i], devHost);
    }
    return {
      project: registry.project,
      registry: registry,
      isDevHost: devHost,
      values: values,
      /** Active value of a flag, as a string. Empty string if undeclared. */
      get: function (name) {
        return Object.prototype.hasOwnProperty.call(values, name) ? values[name] : '';
      },
      /** True iff a toggle/gate flag is on. */
      on: function (name) { return this.get(name) === 'true'; },
      /** The declared default, ignoring any override. */
      defaultOf: function (name) {
        return byName[name] ? declaredDefault(byName[name]) : '';
      },
      /** Ordered options (least-real -> most-real) of a route flag. */
      optionsOf: function (name) {
        return byName[name] && byName[name].options ? byName[name].options.slice() : [];
      },
      /** Persist a dev override. No-op on a production host. */
      set: function (name, value) {
        var flag = byName[name];
        if (!flag || !devHost || !accepts(flag, value)) { return false; }
        lsSet(storageKey(flag), value);
        values[name] = value;
        return true;
      },
      /** Drop a dev override and fall back to the declared default. */
      reset: function (name) {
        var flag = byName[name];
        if (!flag) { return false; }
        lsSet(storageKey(flag), null);
        values[name] = declaredDefault(flag);
        return true;
      },
      /** The env-var line a server needs to match the current dials. */
      envLine: function () {
        var out = [];
        for (var i = 0; i < flags.length; i++) {
          out.push(flags[i].env + '=' + values[flags[i].name]);
        }
        return out.join('\n');
      }
    };
  }

  // ---------------------------------------------------------------------
  // Registry-driven DOM gate. Any element carrying
  // data-flag-gate="<flag name>" is hidden while that gate flag is off. This
  // is generic on purpose: a template opts in with one attribute and no
  // JavaScript is written for it, which is the same "projection, not a
  // per-feature switch" rule the registry itself follows.
  // ---------------------------------------------------------------------
  function applyGates(api, root) {
    var nodes = (root || doc).querySelectorAll('[data-flag-gate]');
    for (var i = 0; i < nodes.length; i++) {
      var name = nodes[i].getAttribute('data-flag-gate');
      nodes[i].hidden = !api.on(name);
    }
  }

  // ---------------------------------------------------------------------
  // Toolbar. Built by iterating the registry — no flag is named here.
  // Styles are injected only on a dev host so a production page ships
  // neither the panel nor its CSS. rem units and flex only (frontend
  // contract); no innerHTML anywhere (every node is createElement).
  // ---------------------------------------------------------------------
  var STYLE = [
    '.mf-devbar{position:fixed;right:1rem;bottom:1rem;z-index:99999;display:flex;',
    'flex-direction:column;align-items:stretch;gap:.5rem;max-width:26rem;',
    'font:.8125rem/1.4 ui-monospace,SFMono-Regular,Menlo,monospace}',
    '.mf-devbar[data-collapsed="true"] .mf-devbar-body{display:none}',
    '.mf-devbar-toggle{display:inline-flex;align-items:center;justify-content:center;',
    'align-self:flex-end;gap:.4rem;padding:.4rem .7rem;border-radius:99rem;',
    'border:.0625rem solid #4f406d;background:#2d2738;color:#fff;cursor:pointer}',
    '.mf-devbar-body{display:flex;flex-direction:column;gap:.5rem;padding:.75rem;',
    'border-radius:.75rem;border:.0625rem solid #4f406d;background:#2d2738;color:#eae4f0;',
    'max-height:70vh;overflow:auto}',
    '.mf-devbar-row{display:flex;flex-direction:column;gap:.2rem}',
    '.mf-devbar-row label{display:flex;align-items:center;gap:.4rem;font-weight:700}',
    '.mf-devbar-row select,.mf-devbar-row input{font:inherit;padding:.25rem .4rem;',
    'border-radius:.4rem;border:.0625rem solid #6e5b91;background:#1f1b26;color:#eae4f0}',
    '.mf-devbar-note{color:#aaa1b3}',
    '.mf-devbar-tag{display:inline-flex;padding:0 .35rem;border-radius:99rem;',
    'background:#6e5b91;color:#fff;font-size:.6875rem}',
    '.mf-devbar-tag.cost{background:#9c4f60}',
    '.mf-devbar-foot{display:flex;flex-direction:column;gap:.25rem}',
    '.mf-devbar-foot textarea{font:inherit;min-height:4rem;border-radius:.4rem;',
    'border:.0625rem solid #6e5b91;background:#1f1b26;color:#eae4f0}'
  ].join('');

  function el(tag, cls, text) {
    var node = doc.createElement(tag);
    if (cls) { node.className = cls; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }

  function mountToolbar(api) {
    if (doc.querySelector('.mf-devbar')) { return; }

    var style = doc.createElement('style');
    style.textContent = STYLE;
    doc.head.appendChild(style);

    var bar = el('aside', 'mf-devbar');
    bar.setAttribute('data-collapsed', lsGet('dev.toolbar.collapsed') === 'false' ? 'false' : 'true');
    bar.setAttribute('aria-label', 'Dev flag toolbar');

    var toggle = el('button', 'mf-devbar-toggle', 'flags (' + (api.registry.flags || []).length + ')');
    toggle.type = 'button';
    toggle.addEventListener('click', function () {
      var collapsed = bar.getAttribute('data-collapsed') === 'true';
      bar.setAttribute('data-collapsed', collapsed ? 'false' : 'true');
      lsSet('dev.toolbar.collapsed', collapsed ? 'false' : 'true');
    });
    bar.appendChild(toggle);

    var body = el('div', 'mf-devbar-body');
    body.appendChild(el('strong', null, api.project + ' — declared variation'));

    var envBox = el('textarea');
    envBox.readOnly = true;

    function refreshEnv() { envBox.value = api.envLine(); }

    var flags = api.registry.flags || [];
    for (var i = 0; i < flags.length; i++) {
      body.appendChild(renderRow(api, flags[i], refreshEnv));
    }

    var foot = el('div', 'mf-devbar-foot');
    foot.appendChild(el('span', 'mf-devbar-note', 'server env for the current dials:'));
    foot.appendChild(envBox);
    var reset = el('button', 'mf-devbar-toggle', 'reset all to declared defaults');
    reset.type = 'button';
    reset.addEventListener('click', function () {
      for (var j = 0; j < flags.length; j++) { api.reset(flags[j].name); }
      global.location.reload();
    });
    foot.appendChild(reset);
    body.appendChild(foot);

    bar.appendChild(body);
    doc.body.appendChild(bar);
    refreshEnv();
  }

  function renderRow(api, flag, refreshEnv) {
    var row = el('div', 'mf-devbar-row');
    var label = el('label');
    label.appendChild(el('span', null, flag.env));
    label.appendChild(el('span', 'mf-devbar-tag', flag.kind + '/' + flag.category));
    if (flag.cost_guard) { label.appendChild(el('span', 'mf-devbar-tag cost', 'cost')); }
    row.appendChild(label);

    var live = flag.binding === 'runtime' && flag.scope !== 'env' && flag.scope !== 'global';
    var control;

    if (flag.effect === 'route') {
      control = doc.createElement('select');
      var options = flag.options || [];
      for (var i = 0; i < options.length; i++) {
        var opt = doc.createElement('option');
        opt.value = options[i];
        opt.textContent = options[i] + (options[i] === api.defaultOf(flag.name) ? ' (default)' : '');
        control.appendChild(opt);
      }
      control.value = api.get(flag.name);
    } else {
      control = doc.createElement('input');
      control.type = 'checkbox';
      control.checked = api.on(flag.name);
    }

    control.disabled = !live;
    control.addEventListener('change', function () {
      var next = flag.effect === 'route' ? control.value : String(control.checked);
      if (flag.cost_guard && next !== api.defaultOf(flag.name)) {
        var ok = global.confirm(
          flag.env + ' = ' + next + ' can incur real cost (paid inference, live buckets).\n' +
          'The declared default ' + api.defaultOf(flag.name) + ' is the guarded one. Continue?'
        );
        if (!ok) {
          if (flag.effect === 'route') { control.value = api.get(flag.name); }
          else { control.checked = api.on(flag.name); }
          return;
        }
      }
      api.set(flag.name, next);
      applyGates(api);
      refreshEnv();
    });
    row.appendChild(control);

    var note = flag.description || '';
    if (!live) {
      note = '[' + (flag.binding === 'compile' ? 'compile-bound' : flag.scope + '-scoped') +
        ' — set ' + flag.env + ' where the service runs, then restart] ' + note;
    }
    row.appendChild(el('small', 'mf-devbar-note', note));
    return row;
  }

  // =====================================================================
  // BOOT — top level. Everything above is a declaration; the four lines
  // below are what actually runs, at parse time, before any sibling
  // script's own top-level code and before any DOMContentLoaded listener
  // anywhere in the page has been invoked.
  // =====================================================================
  var currentScript = doc.currentScript;
  if (currentScript && (currentScript.defer || currentScript.async)) {
    // A deferred/async load re-introduces exactly the bug the banner
    // describes, so say so loudly instead of resolving wrong values quietly.
    global.console.error(
      '[flags] this script must be a plain, in-order <script src> tag: ' +
      'defer/async delays flag resolution past other scripts\' boot.'
    );
  }

  var devHost = isDevHost(global.location ? global.location.hostname : '');
  ingestQueryOverrides(REGISTRY.flags || [], global.location ? global.location.search : '');
  var api = buildApi(REGISTRY, devHost);
  global.DevFlags = api;

  // DOM work only — no resolved value changes below this line.
  function afterDom() {
    applyGates(api);
    if (devHost) { mountToolbar(api); }
  }
  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', afterDom);
  } else {
    afterDom();
  }
})(window, document);
