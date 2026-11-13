#!/usr/bin/env bash
# Behaviour lock for scripts/validate-metric-registry.py.
#
# The validator exists to make a registry's claims checkable, so the one thing
# that must never rot is its ability to REJECT. A validator that silently
# accepts everything passes any suite built only from valid fixtures — so every
# negative case below also asserts the specific message, meaning a fixture
# cannot pass for the wrong reason (a JSON typo failing instead of the rule
# under test).
#
# Fixtures are inline rather than checked-in files so a reader sees the input
# and the expected verdict together, and so an intentionally-invalid registry
# never sits in metrics/ where another tool might pick it up as real.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$repo_root/scripts/validate-metric-registry.py"
schema="$repo_root/metrics/metric-registry.schema.json"

for required in "$validator" "$schema"; do
  if [[ ! -f "$required" ]]; then
    echo "FAIL: $required not found" >&2
    exit 1
  fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

run_validator() {
  local target="$tmpdir/registry.json"
  cat > "$target"
  python3 "$validator" --schema "$schema" "$target" 2>&1
}

# expect_ok <label>  — registry on stdin must validate cleanly.
expect_ok() {
  local label="$1" out rc=0
  out=$(run_validator) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf '  ok    accept  %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL  accept  %s  (rejected, rc=%s)\n' "$label" "$rc"
    printf '        %s\n' "$out"
    fail=$((fail + 1))
  fi
}

# expect_fail <label> <needle> — must be rejected, and the output must mention
# <needle> so the right rule is doing the rejecting.
expect_fail() {
  local label="$1" needle="$2" out rc=0
  out=$(run_validator) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf '  FAIL  reject  %s  (accepted)\n' "$label"
    fail=$((fail + 1))
  elif printf '%s' "$out" | grep -qF -- "$needle"; then
    printf '  ok    reject  %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL  reject  %s  (rejected, but not for the expected reason)\n' "$label"
    printf '        wanted: %s\n' "$needle"
    printf '        got:    %s\n' "$out"
    fail=$((fail + 1))
  fi
}

echo "-- a realistic registry validates --"

# Exercises every kind and every population that can stand alone, plus the
# reasoned-exception branch: an edge-measured baseline has no browser scenario
# to cover it, which is a real gap with a real reason rather than an oversight.
expect_ok "all kinds, all populations, a reasoned exception" <<'JSON'
{
  "version": 1,
  "project": "selftest",
  "metrics": [
    {
      "name": "site_page_views",
      "title": "Page views",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "source": { "signal": "cloudfront:cs-uri-stem", "store": "access-logs" },
      "seam": "src/traffic.py:page_views",
      "exceptions": [
        {
          "scope": "coverage",
          "reason": "measured at the edge from access logs, so no browser scenario can produce or withhold it",
          "added": "2026-11-13"
        }
      ]
    },
    {
      "name": "form_funnel_starts",
      "title": "Form funnel starts",
      "kind": "count",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "baseline": "site_page_views",
      "source": { "signal": "form/focus" },
      "coverage": ["form-funnel-complete"],
      "seam": "src/aggregate.rs:funnels"
    },
    {
      "name": "form_funnel_conversion",
      "title": "Form funnel conversion",
      "kind": "rate",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "baseline": "site_page_views",
      "source": { "signal": "form/submit", "excludes": ["error", "abandoned", "blocked"] },
      "denominator": "form_funnel_starts",
      "min_sample": 30,
      "coverage": ["form-funnel-complete", "guard-form-submit-rejected"],
      "seam": "src/aggregate.rs:funnels"
    },
    {
      "name": "dwell_ms",
      "title": "Time on page",
      "kind": "distribution",
      "surface": "rollup",
      "population": "consenting-visitor",
      "baseline": "site_page_views",
      "source": { "signal": "page/exit" },
      "min_sample": 30,
      "coverage": ["traffic-deep-read"],
      "seam": "src/metrics.py:path_stats"
    },
    {
      "name": "grammar_coverage",
      "title": "Events by interaction kind",
      "kind": "count",
      "surface": "rollup",
      "population": "mixed",
      "description": "Spans visitor and internal traffic deliberately: this answers whether anything is arriving at all, which an internal-only run must not hide.",
      "source": { "signal": "*" },
      "coverage": ["traffic-deep-read"],
      "seam": "src/metrics.py:_build_health"
    },
    {
      "name": "harness_batches",
      "title": "Harness batches",
      "kind": "count",
      "surface": "coverage-report",
      "population": "synthetic",
      "source": { "signal": "batch" },
      "coverage": ["traffic-deep-read"],
      "seam": "tests/e2e/report.ts"
    }
  ]
}
JSON

expect_ok "an empty registry" <<'JSON'
{ "version": 1, "metrics": [] }
JSON

echo
echo "-- the consent rule: a subset population must name a baseline --"

expect_fail "consenting-visitor without a baseline" 'requires `baseline`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "sessions",
      "title": "Sessions",
      "kind": "count",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "source": { "signal": "page/view" },
      "coverage": ["traffic-deep-read"]
    }
  ]
}
JSON

expect_fail "baseline that is itself consent-gated" "not 'all-traffic'" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "tracked_views",
      "title": "Tracked views",
      "kind": "count",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "baseline": "tracked_sessions",
      "source": { "signal": "page/view" },
      "coverage": ["traffic-deep-read"]
    },
    {
      "name": "tracked_sessions",
      "title": "Tracked sessions",
      "kind": "count",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "baseline": "tracked_views",
      "source": { "signal": "page/view" },
      "coverage": ["traffic-deep-read"]
    }
  ]
}
JSON

expect_fail "baseline naming a metric that does not exist" 'baseline `nowhere` is not a declared metric' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "sessions",
      "title": "Sessions",
      "kind": "count",
      "surface": "weekly-report",
      "population": "consenting-visitor",
      "baseline": "nowhere",
      "source": { "signal": "page/view" },
      "coverage": ["traffic-deep-read"]
    }
  ]
}
JSON

expect_fail "all-traffic carrying a redundant baseline" 'must not carry `baseline`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "views",
      "title": "Views",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "baseline": "views_other",
      "source": { "signal": "cloudfront" },
      "coverage": ["x"]
    },
    {
      "name": "views_other",
      "title": "Views (other)",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "source": { "signal": "cloudfront" },
      "coverage": ["x"]
    }
  ]
}
JSON

echo
echo "-- quotients must name what they are over, and over how many --"

expect_fail "rate with no denominator" 'requires `denominator`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "conversion",
      "title": "Conversion",
      "kind": "rate",
      "surface": "weekly-report",
      "population": "all-traffic",
      "min_sample": 30,
      "source": { "signal": "form/submit" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "rate with no min_sample" 'kind=rate requires `min_sample`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "conversion",
      "title": "Conversion",
      "kind": "rate",
      "surface": "weekly-report",
      "population": "all-traffic",
      "denominator": "starts",
      "source": { "signal": "form/submit" },
      "coverage": ["x"]
    },
    {
      "name": "starts",
      "title": "Starts",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "source": { "signal": "form/focus" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "distribution with no min_sample" 'kind=distribution requires `min_sample`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "dwell",
      "title": "Dwell",
      "kind": "distribution",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "page/exit" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "count carrying a denominator" 'must not carry `denominator`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "views",
      "title": "Views",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "denominator": "sessions",
      "source": { "signal": "page/view" },
      "coverage": ["x"]
    },
    {
      "name": "sessions",
      "title": "Sessions",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "page/view" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "denominator naming a metric that does not exist" 'denominator `ghost` is not a declared metric' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "conversion",
      "title": "Conversion",
      "kind": "rate",
      "surface": "weekly-report",
      "population": "all-traffic",
      "denominator": "ghost",
      "min_sample": 30,
      "source": { "signal": "form/submit" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "denominator pointing at itself" "denominator refers to itself" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "conversion",
      "title": "Conversion",
      "kind": "rate",
      "surface": "weekly-report",
      "population": "all-traffic",
      "denominator": "conversion",
      "min_sample": 30,
      "source": { "signal": "form/submit" },
      "coverage": ["x"]
    }
  ]
}
JSON

echo
echo "-- a number nothing exercises is vacuous --"

expect_fail "no coverage and no exception" "vacuous" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "top_ctas",
      "title": "Top CTAs",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "source": { "signal": "cta/click" }
    }
  ]
}
JSON

expect_fail "no coverage and only a placeholder excuse" "explains nothing" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "top_ctas",
      "title": "Top CTAs",
      "kind": "count",
      "surface": "weekly-report",
      "population": "all-traffic",
      "source": { "signal": "cta/click" },
      "exceptions": [{ "scope": "coverage", "reason": "TODO" }]
    }
  ]
}
JSON

echo
echo "-- a blended population must say what it blends --"

expect_fail "mixed with no description" 'population=mixed requires a `description`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "all_events",
      "title": "All events",
      "kind": "count",
      "surface": "rollup",
      "population": "mixed",
      "source": { "signal": "*" },
      "coverage": ["x"]
    }
  ]
}
JSON

echo
echo "-- structural rules --"

expect_fail "unknown kind" "is not one of" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "average",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "s" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "unknown population" "is not one of" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "count",
      "surface": "rollup",
      "population": "everyone",
      "source": { "signal": "s" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "name that is not snake_case" "does not match" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "Top-CTAs",
      "title": "X",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "s" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "source with no signal" 'source is missing required key `signal`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "store": "dynamo" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "negative min_sample" "non-negative integer" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "distribution",
      "surface": "rollup",
      "population": "all-traffic",
      "min_sample": -1,
      "source": { "signal": "s" },
      "coverage": ["x"]
    }
  ]
}
JSON

expect_fail "duplicate metric name" "duplicate name" <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "s" },
      "coverage": ["a"]
    },
    {
      "name": "x",
      "title": "X again",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "s" },
      "coverage": ["a"]
    }
  ]
}
JSON

expect_fail "unknown key on a metric" 'unknown key `units`' <<'JSON'
{
  "version": 1,
  "metrics": [
    {
      "name": "x",
      "title": "X",
      "kind": "count",
      "surface": "rollup",
      "population": "all-traffic",
      "source": { "signal": "s" },
      "coverage": ["x"],
      "units": "ms"
    }
  ]
}
JSON

expect_fail "wrong registry version" "version must be 1" <<'JSON'
{ "version": 2, "metrics": [] }
JSON

expect_fail "missing required top-level key" 'missing required key `metrics`' <<'JSON'
{ "version": 1 }
JSON

echo
# An extraction failure must be LOUD. If the schema is ever restructured so the
# enums no longer resolve, the validator has to exit 2 rather than treat every
# value as valid — the failure mode that makes a gate worthless.
echo "-- a schema it cannot read fails loudly, it does not pass --"
stub_schema="$tmpdir/stub-schema.json"
printf '{"type":"object","required":["version","metrics"],"properties":{"version":{},"metrics":{}}}\n' > "$stub_schema"
printf '{"version":1,"metrics":[]}\n' > "$tmpdir/minimal.json"
extraction_rc=0
extraction_out=$(python3 "$validator" --schema "$stub_schema" "$tmpdir/minimal.json" 2>&1) || extraction_rc=$?
if [[ "$extraction_rc" -eq 2 ]] && printf '%s' "$extraction_out" | grep -qF "could not extract from the schema"; then
  printf '  ok    unreadable schema exits 2\n'
  pass=$((pass + 1))
else
  printf '  FAIL  unreadable schema should exit 2 with a clear message (rc=%s)\n' "$extraction_rc"
  printf '        got: %s\n' "$extraction_out"
  fail=$((fail + 1))
fi

echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "metric-registry validator OK (accepts valid registries, rejects each violation class)"
