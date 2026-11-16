#!/usr/bin/env bash
# Behaviour lock for scripts/metric-coverage-report.py.
#
# Both directions, deliberately. A reporter that always exits 0 passes every
# "this clean registry is clean" case, and a reporter that always exits 1
# passes every "this broken registry is broken" case. Only the pair pins it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/metric-coverage-report.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# expect <want-exit> <label> -- <args...>
expect() {
  local want="$1" label="$2"; shift 3
  local out
  out="$(python3 "$REPORT" "$@" 2>&1)"
  local got=$?
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     wanted exit %s, got %s\n' "$label" "$want" "$got"
    printf '     %s\n' "$out"
  fi
}

# expect_text <label> <needle> -- <args...>
expect_text() {
  local label="$1" needle="$2"; shift 3
  local out
  out="$(python3 "$REPORT" "$@" 2>&1)"
  if grep -qF -- "$needle" <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     output did not contain: %s\n' "$label" "$needle"
    printf '     %s\n' "$out"
  fi
}

registry() {
  cat >"$TMP/$1"
}

mkdir -p "$TMP/scenarios"
: >"$TMP/scenarios/deep-read.spec.ts"
: >"$TMP/scenarios/cta-click.spec.ts"
: >"$TMP/scenarios/nobody-names-me.spec.ts"

registry covered.json <<'JSON'
{
  "version": 1,
  "project": "covered",
  "metrics": [
    { "name": "a", "title": "A", "kind": "count", "surface": "s", "population": "all-traffic",
      "source": { "signal": "x" }, "coverage": ["deep-read"] },
    { "name": "b", "title": "B", "kind": "count", "surface": "s", "population": "all-traffic",
      "source": { "signal": "y" }, "coverage": ["cta-click"] }
  ]
}
JSON

registry dangling.json <<'JSON'
{
  "version": 1,
  "project": "dangling",
  "metrics": [
    { "name": "a", "title": "A", "kind": "count", "surface": "s", "population": "all-traffic",
      "source": { "signal": "x" }, "coverage": ["deep-read", "renamed-away"] }
  ]
}
JSON

registry exceptional.json <<'JSON'
{
  "version": 1,
  "project": "exceptional",
  "metrics": [
    { "name": "a", "title": "A", "kind": "count", "surface": "s", "population": "all-traffic",
      "source": { "signal": "x" },
      "exceptions": [{ "scope": "coverage", "reason": "no scenario can produce a CDN log row",
                       "added": "2020-01-01" }] }
  ]
}
JSON

registry vacuous.json <<'JSON'
{
  "version": 1,
  "project": "vacuous",
  "metrics": [
    { "name": "a", "title": "A", "kind": "count", "surface": "s", "population": "all-traffic",
      "source": { "signal": "x" } }
  ]
}
JSON

registry empty.json <<'JSON'
{ "version": 1, "project": "empty", "metrics": [] }
JSON

echo '{ not json' >"$TMP/broken.json"
echo '[]' >"$TMP/array.json"

# --- the pair that matters ---------------------------------------------------
expect 0 "a fully covered registry is clean" -- "$TMP/covered.json" --scenarios "$TMP/scenarios"
expect 1 "a coverage id matching no scenario fails" -- "$TMP/dangling.json" --scenarios "$TMP/scenarios"
expect_text "the failure names the metrics that lost their proof" "metric(s) claim a proof that does not exist" -- "$TMP/dangling.json" --scenarios "$TMP/scenarios"
expect_text "the table marks the dangling id inline" "NO SUCH SCENARIO" -- "$TMP/dangling.json" --scenarios "$TMP/scenarios"

# --- exceptions are reported, never failed -----------------------------------
expect 0 "an exception-only registry does not fail" -- "$TMP/exceptional.json" --scenarios "$TMP/scenarios"
expect_text "an exception-only registry says the numbers are unproven" "declared, not proven" -- "$TMP/exceptional.json" --scenarios "$TMP/scenarios"
expect_text "a long-standing exception is surfaced as stale" "days" -- "$TMP/exceptional.json" --scenarios "$TMP/scenarios"

# --- a registry the validator would reject -----------------------------------
expect_text "a metric with neither coverage nor exception is called vacuous" "VACUOUS" -- "$TMP/vacuous.json" --scenarios "$TMP/scenarios"
expect_text "and says the registry is therefore ungated" "this registry is not gated" -- "$TMP/vacuous.json" --scenarios "$TMP/scenarios"

# --- scenarios nothing names --------------------------------------------------
expect_text "a scenario no metric names is reported" "nobody-names-me" -- "$TMP/covered.json" --scenarios "$TMP/scenarios"
expect 0 "an unnamed scenario is not a failure" -- "$TMP/covered.json" --scenarios "$TMP/scenarios"

# --- an empty registry is not 0% ---------------------------------------------
expect_text "an empty registry reports n/a rather than 0%" "n/a" -- "$TMP/empty.json" --scenarios "$TMP/scenarios"

# --- without --scenarios nothing can fail ------------------------------------
expect 0 "a dangling id cannot be detected without a corpus" -- "$TMP/dangling.json"
expect_text "and the report still describes the registry" "coverage" -- "$TMP/dangling.json"

# --- machine-readable ---------------------------------------------------------
expect_text "--json emits the dangling map" "dangling_coverage" -- "$TMP/dangling.json" --scenarios "$TMP/scenarios" --json
expect_text "--json omits the dangling map with no corpus" "coverage_pct" -- "$TMP/dangling.json" --json

# --- tooling failures are exit 2, distinct from a finding ---------------------
expect 2 "an unreadable registry is a usage error, not a finding" -- "$TMP/broken.json"
expect 2 "a JSON array is not a registry" -- "$TMP/array.json"
expect 2 "a missing scenarios dir is a usage error" -- "$TMP/covered.json" --scenarios "$TMP/nope"
mkdir -p "$TMP/no-scenarios"
expect 2 "an EMPTY corpus is a tooling failure, not 100% dangling" -- "$TMP/covered.json" --scenarios "$TMP/no-scenarios"

# --- several registries at once ------------------------------------------------
expect 1 "one broken registry among several still fails" -- "$TMP/covered.json" "$TMP/dangling.json" --scenarios "$TMP/scenarios"
expect_text "and both are described" "project" -- "$TMP/covered.json" "$TMP/dangling.json" --scenarios "$TMP/scenarios" --json

printf '\nmetric-coverage-report selftest: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
