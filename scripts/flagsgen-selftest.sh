#!/usr/bin/env bash
# flagsgen-selftest.sh — behaviour lock for flags/flagsgen.py.
#
# Hermetic: builds its own throwaway registry in a temp dir, never touches the
# repo's own flags/. Runs on nothing but python3 + the repo's schema; the
# `validate` cases are skipped (loudly, never silently) when `jsonschema` is
# absent, because flagsgen deliberately refuses to validate without it.
#
# What is locked here is the set of properties consumers depend on:
#   1. the emitted JS resolves flags at parse time, NOT inside DOMContentLoaded
#   2. the emitted JS names no flag — it iterates the registry
#   3. every emitted file carries a registry-sha256 provenance header
#   4. `check` fails when the registry moves and the projection does not
#   5. `validate` rejects an adapter flag whose default is not the cheapest option
#   6. an explicit `env` overrides the uppercased-name derivation
#   7. the `$schema` key the rule doc tells authors to write is accepted
#      (it was not, and the emitted JS must not carry it into the browser)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAGSGEN="$REPO_ROOT/flags/flagsgen.py"
SCHEMA="$REPO_ROOT/flags/flag-registry.schema.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
pass() { printf '  ok  %s\n' "$*"; }

cat >"$TMP/flags.json" <<'JSON'
{
  "$schema": "https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards/main/flags/flag-registry.schema.json",
  "version": 1,
  "project": "selftest",
  "flags": [
    {
      "name": "widget_store",
      "kind": "adapter",
      "category": "data",
      "binding": "runtime",
      "effect": "route",
      "options": ["memory", "dynamodb"],
      "default": "memory",
      "seam": "src/store.rs",
      "scope": "env",
      "description": "selftest adapter"
    },
    {
      "name": "widget_api_base",
      "kind": "value",
      "category": "infra",
      "binding": "runtime",
      "effect": "toggle",
      "value_type": "url",
      "default": "",
      "env": "PREFIXED_WIDGET_API_BASE",
      "scope": "env",
      "description": "selftest prefixed env name"
    },
    {
      "name": "heavy_thing",
      "kind": "gate",
      "category": "feature",
      "binding": "runtime",
      "effect": "toggle",
      "default": false,
      "seam": "src/heavy.rs",
      "scope": "session",
      "cost_guard": true,
      "description": "selftest gate"
    }
  ]
}
JSON

python3 "$FLAGSGEN" emit-js --registry "$TMP/flags.json" --out "$TMP/flags.js" >/dev/null
python3 "$FLAGSGEN" emit-env --registry "$TMP/flags.json" --out "$TMP/flags.env" >/dev/null

# 1. Synchronous boot. The only DOMContentLoaded registration must come AFTER
#    the resolver has already been built and published, and the function it
#    registers must not be the one that applies overrides.
grep -q 'ingestQueryOverrides(REGISTRY' "$TMP/flags.js" ||
  fail "emitted JS never applies overrides at top level"
boot_line=$(grep -n 'global.DevFlags = api;' "$TMP/flags.js" | head -1 | cut -d: -f1)
dcl_line=$(grep -n "addEventListener('DOMContentLoaded'" "$TMP/flags.js" | head -1 | cut -d: -f1)
[ -n "$boot_line" ] || fail "emitted JS never publishes the resolver"
[ -n "$dcl_line" ] || fail "emitted JS has no deferred DOM mount at all"
[ "$boot_line" -lt "$dcl_line" ] ||
  fail "resolution (line $boot_line) must precede the DOMContentLoaded mount (line $dcl_line)"
dcl_count=$(grep -c "addEventListener('DOMContentLoaded'" "$TMP/flags.js")
[ "$dcl_count" -eq 1 ] || fail "expected exactly one DOMContentLoaded registration, found $dcl_count"
pass "overrides are applied synchronously, before the single deferred DOM mount"

# 2. Generated, not hand-written: the executable body must not name any flag.
body=$(sed -n '/^(function (global, doc)/,$p' "$TMP/flags.js")
for name in widget_store widget_api_base heavy_thing; do
  printf '%s' "$body" | grep -q "$name" &&
    fail "emitted JS body hardcodes the flag name '$name' instead of iterating the registry"
done
pass "toolbar body names no flag — it iterates the inlined registry"

# 3. Provenance header on every projection.
want_sha=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$TMP/flags.json")
for f in "$TMP/flags.js" "$TMP/flags.env"; do
  grep -q "registry-sha256: $want_sha" "$f" || fail "$f is missing its registry-sha256 header"
done
pass "every projection records the registry checksum it was built from"

# 4. Drift gate.
python3 "$FLAGSGEN" check --registry "$TMP/flags.json" \
  --generated "$TMP/flags.js" --generated "$TMP/flags.env" >/dev/null ||
  fail "check reported drift on freshly generated files"
cp "$TMP/flags.json" "$TMP/moved.json"
printf '\n' >>"$TMP/moved.json"
if python3 "$FLAGSGEN" check --registry "$TMP/moved.json" --generated "$TMP/flags.js" >/dev/null 2>&1; then
  fail "check passed after the registry changed — the drift gate is inert"
fi
pass "check fails once the registry moves away from the committed projection"

# 6. Explicit env overrides the derived name.
grep -q '^PREFIXED_WIDGET_API_BASE=' "$TMP/flags.env" ||
  fail "explicit env name was not honoured in the env projection"
grep -q '^WIDGET_API_BASE=' "$TMP/flags.env" &&
  fail "derived env name leaked despite an explicit env field"
grep -q '^WIDGET_STORE=memory$' "$TMP/flags.env" ||
  fail "derived env name / guarded default missing from the env projection"
pass "env names: explicit wins, otherwise derived from the flag name"

# 5. Cost guard (needs jsonschema; flagsgen refuses to validate without it).
if python3 -c 'import jsonschema' 2>/dev/null; then
  python3 "$FLAGSGEN" validate --registry "$TMP/flags.json" --schema "$SCHEMA" >/dev/null ||
    fail "the selftest registry does not validate against the shipped schema"
  sed 's/"default": "memory"/"default": "dynamodb"/' "$TMP/flags.json" >"$TMP/bad.json"
  if python3 "$FLAGSGEN" validate --registry "$TMP/bad.json" --schema "$SCHEMA" >/dev/null 2>&1; then
    fail "an adapter defaulting to the expensive option passed validation"
  fi
  pass "validate rejects an adapter flag that does not default to the cheapest option"
  grep -q '"\$schema"' "$TMP/flags.json" || fail "selftest registry lost its \$schema key"
  pass "a registry carrying the documented \$schema key validates"
  grep -q '"\$schema"' "$TMP/flags.js" &&
    fail "the schema URL was inlined into the browser bundle; strip it in emit-js"
  pass "emit-js strips \$schema — the browser has no use for a validator URL"
else
  printf '  SKIP validate cases: jsonschema is not installed (pip install jsonschema)\n'
fi

printf 'flagsgen selftest: PASS\n'
