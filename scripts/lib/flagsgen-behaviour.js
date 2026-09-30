// Behaviour lock for the toolbar flags/flagsgen.py emits.
//
// scripts/flagsgen-selftest.sh asserts the emitted file's STRUCTURE — that
// resolution precedes the single deferred DOM mount, that no flag is named in
// the body. This asserts what it actually DOES, by executing it against a stub
// DOM: the structural checks cannot tell a working resolver from one that
// resolves the wrong value.
//
// The claim that matters most here is the cost guard. On a production hostname
// a stored override must be IGNORED, not merely hidden — otherwise a dial left
// set months ago in a dev session silently re-routes a real visitor's traffic,
// and for an adapter flag that means billing real inference.
//
// Usage: node flagsgen-behaviour.js <emitted-flags.js>
// The registry it is run against must declare detector_backend (api) and
// detector_store (data); the selftest generates exactly that fixture.
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');

function run(hostname, stored, search) {
  const store = { ...stored };
  const listeners = [];
  const doc = {
    readyState: 'loading',
    currentScript: { defer: false, async: false },
    addEventListener: (ev, fn) => listeners.push(ev),
    querySelectorAll: () => [],
    createElement: () => ({ appendChild(){}, addEventListener(){}, setAttribute(){}, dataset:{}, classList:{} }),
    head: { appendChild(){} }, body: { appendChild(){} },
    querySelector: () => null,
  };
  const win = {
    location: { hostname, search: search || '' },
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = v; },
      removeItem: k => { delete store[k]; },
    },
    console: { error: () => {} },
    confirm: () => true,
  };
  const ctx = vm.createContext({ window: win, document: doc });
  vm.runInContext(src, ctx);
  return { api: win.DevFlags, store, listeners };
}

let failures = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) failures++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${name} — got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
};

let r = run('localhost', {});
check('dev host: defaults resolve', r.api.get('detector_backend'), 'mock');
check('dev host: recognised as dev', r.api.isDevHost, true);
check('gate is off by default', r.api.on('videoseal_detector'), false);
check('exactly one DOMContentLoaded listener registered', r.listeners, ['DOMContentLoaded']);

r = run('localhost', { 'dev.route.api.detector_backend': 'engine' });
check('dev host: stored override applies', r.api.get('detector_backend'), 'engine');

r = run('www.example.com', { 'dev.route.api.detector_backend': 'engine' });
check('PROD host: stored override IGNORED (cost guard)', r.api.get('detector_backend'), 'mock');
check('PROD host: not a dev host', r.api.isDevHost, false);

r = run('localhost', {}, '?flag.api.detector_backend=engine');
check('query override applies synchronously', r.api.get('detector_backend'), 'engine');

r = run('localhost', {}, '?flag.api.detector_backend=bogus');
check('undeclared query value rejected', r.api.get('detector_backend'), 'mock');

r = run('localhost', { 'dev.route.data.detector_store': 'dynamodb' });
check('env line reflects the dials',
  r.api.envLine().split('\n').filter(l => l.startsWith('DETECTOR_STORE='))[0],
  'DETECTOR_STORE=dynamodb');

r = run('localhost', {});
check('set() then get() round-trips', (r.api.set('detector_store','dynamodb'), r.api.get('detector_store')), 'dynamodb');
check('reset() returns to the declared default', (r.api.reset('detector_store'), r.api.get('detector_store')), 'memory');

process.exit(failures ? 1 : 0);
