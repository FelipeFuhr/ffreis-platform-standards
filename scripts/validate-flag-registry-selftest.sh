#!/usr/bin/env bash
# Behaviour lock for scripts/validate-flag-registry.py.
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
# never sits in flags/ where another tool might pick it up as real.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$repo_root/scripts/validate-flag-registry.py"
schema="$repo_root/flags/flag-registry.schema.json"
vocabulary="$repo_root/flags/quality-rules.md"

for required in "$validator" "$schema" "$vocabulary"; do
  if [[ ! -f "$required" ]]; then
    echo "FAIL: $required not found" >&2
    exit 1
  fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

# run_validator — feeds stdin to the validator as a registry file.
run_validator() {
  local target="$tmpdir/registry.json"
  cat > "$target"
  python3 "$validator" --schema "$schema" --vocabulary "$vocabulary" "$target" 2>&1
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

# expect_fail <label> <needle>  — registry on stdin must be rejected, and the
# output must mention <needle> so the right rule is doing the rejecting.
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

# An extraction failure must be LOUD. If the vocabulary ever stops yielding
# rule ids (renamed file, restructured headings), the validator has to exit 2
# rather than treat every `rule` value as unknown — or worse, as fine. The
# happy path is covered implicitly: the valid fixture below declares two
# quality rules, which can only pass if extraction actually worked.
echo "-- an unreadable or empty vocabulary fails loudly, it does not pass --"
empty_vocab="$tmpdir/empty-vocabulary.md"
: > "$empty_vocab"
printf '{"version":1,"flags":[]}\n' > "$tmpdir/minimal.json"
extraction_rc=0
extraction_out=$(python3 "$validator" --schema "$schema" --vocabulary "$empty_vocab" \
  "$tmpdir/minimal.json" 2>&1) || extraction_rc=$?
if [[ "$extraction_rc" -eq 2 ]] && printf '%s' "$extraction_out" | grep -qF "no quality rules found"; then
  printf '  ok    empty vocabulary exits 2\n'
  pass=$((pass + 1))
else
  printf '  FAIL  empty vocabulary should exit 2 with a clear message (rc=%s)\n' "$extraction_rc"
  printf '        got: %s\n' "$extraction_out"
  fail=$((fail + 1))
fi

echo
# A heading that LOOKS like a rule but is not a well-formed id must be
# reported here, not skipped. Skipping registers no rule, and the only symptom
# would be a later "not in the vocabulary" rejection against the registry —
# sending the reader to the wrong file to hunt a typo that lives in this one.
echo "-- a malformed or duplicated rule heading is reported, not skipped --"

# expect_vocabulary_error <label> <needle> ; vocabulary body on stdin
expect_vocabulary_error() {
  local label="$1" needle="$2" vocab="$tmpdir/vocabulary.md" out rc=0
  cat > "$vocab"
  out=$(python3 "$validator" --schema "$schema" --vocabulary "$vocab" \
    "$tmpdir/minimal.json" 2>&1) || rc=$?
  if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -qF -- "$needle"; then
    printf '  ok    %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s  (rc=%s, wanted %s)\n' "$label" "$rc" "$needle"
    printf '        got: %s\n' "$out"
    fail=$((fail + 1))
  fi
}

expect_vocabulary_error "uppercase rule id" "malformed rule id" <<'MD'
### `Font-Integrity`
MD

expect_vocabulary_error "rule id with spaces" "malformed rule id" <<'MD'
### `font integrity`
MD

expect_vocabulary_error "duplicated rule id" "duplicate rule id" <<'MD'
### `font-integrity`

### `font-integrity`
MD

echo
echo "-- a fully valid registry, exercising every kind and both quality shapes --"
expect_ok "all four kinds + enforcing and non-enforcing quality" <<'JSON'
{
  "$schema": "https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards/main/flags/flag-registry.schema.json",
  "version": 1,
  "project": "selftest",
  "flags": [
    {
      "name": "transport", "kind": "service", "category": "api",
      "binding": "runtime", "effect": "route",
      "options": ["fake", "live"], "default": "fake", "seam": "ctx::api_base"
    },
    {
      "name": "image_provider", "kind": "adapter", "category": "model",
      "binding": "runtime", "effect": "route",
      "options": ["mock", "live"], "default": "mock",
      "cost_guard": true, "seam": "resolver::image"
    },
    {
      "name": "items_per_page", "kind": "value", "category": "content",
      "binding": "compile", "effect": "route", "options": ["12", "24"],
      "value_type": "enum", "default": "12", "seam": "pagination::page_size"
    },
    {
      "name": "dev_panel", "kind": "gate", "category": "feature",
      "binding": "compile", "effect": "toggle", "default": false,
      "seam": "view_develop"
    },
    {
      "name": "font_integrity", "kind": "gate", "category": "quality",
      "binding": "compile", "effect": "toggle", "default": true,
      "rule": "font-integrity", "output_target": "document-export",
      "seam": "tests/fonts_test.go TestDeclaredFamilyIsEmbedded"
    },
    {
      "name": "output_gate_pdf", "kind": "value", "category": "quality",
      "binding": "compile", "effect": "route",
      "options": ["error", "warn", "off"], "value_type": "enum",
      "default": "off", "rule": "output-gate-exists",
      "output_target": ["document-export", "raster-export"],
      "exceptions": [
        {
          "scope": "the PDF target",
          "reason": "no text-extraction gate exists for this target yet; the only check is that the file was written, which passes for an empty document",
          "added": "2026-10-16"
        }
      ]
    }
  ]
}
JSON

echo
echo "-- quality conformance: the rules that keep a declaration honest --"
expect_fail "quality rule not in the vocabulary" "is not in the vocabulary" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": true, "rule": "font-integritee",
      "seam": "tests/x_test.go"
    }
  ]
}
JSON

expect_fail "enforcing quality rule names no seam" "names no \`seam\`" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": true, "rule": "font-integrity"
    }
  ]
}
JSON

expect_fail "non-enforcing quality rule gives no reason" "gives no reason" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": false, "rule": "font-integrity"
    }
  ]
}
JSON

expect_fail "quality entry without a rule" "requires \`rule\`" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": true, "seam": "tests/x_test.go"
    }
  ]
}
JSON

expect_fail "rule declared on a non-quality flag" "only meaningful for category=quality" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "feature", "binding": "compile",
      "effect": "toggle", "default": true, "rule": "font-integrity"
    }
  ]
}
JSON

echo
echo "-- exceptions must actually explain something --"
expect_fail "placeholder reason" "explains nothing" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": false, "rule": "contrast-aa",
      "exceptions": [{ "scope": "everything", "reason": "TODO" }]
    }
  ]
}
JSON

expect_fail "reason too short to be a reason" "explains nothing" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": false, "rule": "contrast-aa",
      "exceptions": [{ "scope": "everything", "reason": "not needed" }]
    }
  ]
}
JSON

expect_fail "exception missing its scope" "missing required key \`scope\`" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": false, "rule": "contrast-aa",
      "exceptions": [{ "reason": "the token definition file is the one place literals may appear" }]
    }
  ]
}
JSON

echo
echo "-- the cost guard, previously documented but unenforced --"
expect_fail "model flag defaulting to the paid option" "cheapest option" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "image_provider", "kind": "adapter", "category": "model",
      "binding": "runtime", "effect": "route",
      "options": ["mock", "live"], "default": "live", "seam": "resolver"
    }
  ]
}
JSON

expect_ok "model flag defaulting to paid WITH a justification" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "image_provider", "kind": "adapter", "category": "model",
      "binding": "runtime", "effect": "route",
      "options": ["mock", "live"], "default": "live", "seam": "resolver",
      "exceptions": [
        {
          "scope": "production builds only",
          "reason": "prod must reach the real provider; dev and CI override this to mock via environment scope"
        }
      ]
    }
  ]
}
JSON

echo
echo "-- structural checks (extracted from the schema, not duplicated here) --"
expect_fail "unknown category" "is not one of" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "qualty", "binding": "compile",
      "effect": "toggle", "default": true, "seam": "x"
    }
  ]
}
JSON

expect_fail "unknown output_target class" "output_target" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "quality", "binding": "compile",
      "effect": "toggle", "default": true, "rule": "contrast-aa",
      "output_target": "browser", "seam": "x"
    }
  ]
}
JSON

expect_fail "route effect with no options" "requires \`options\`" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "service", "category": "api", "binding": "runtime",
      "effect": "route", "default": "a", "seam": "x"
    }
  ]
}
JSON

expect_fail "gate with a route effect" "must have effect=toggle" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "feature", "binding": "compile",
      "effect": "route", "options": ["a", "b"], "default": "a", "seam": "x"
    }
  ]
}
JSON

expect_fail "value kind without value_type" "requires \`value_type\`" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "value", "category": "feature", "binding": "compile",
      "effect": "toggle", "default": 1, "seam": "x"
    }
  ]
}
JSON

expect_fail "default that is not one of its own options" "is not one of its options" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "service", "category": "api", "binding": "runtime",
      "effect": "route", "options": ["a", "b"], "default": "c", "seam": "x"
    }
  ]
}
JSON

expect_fail "duplicate flag name" "duplicate name" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "dup", "kind": "gate", "category": "feature", "binding": "compile",
      "effect": "toggle", "default": true, "seam": "x"
    },
    {
      "name": "dup", "kind": "gate", "category": "feature", "binding": "compile",
      "effect": "toggle", "default": false, "seam": "y"
    }
  ]
}
JSON

expect_fail "unknown key on a flag" "unknown key" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "q", "kind": "gate", "category": "feature", "binding": "compile",
      "effect": "toggle", "default": true, "seam": "x", "notAField": 1
    }
  ]
}
JSON

expect_fail "uppercase flag name" "does not match" <<'JSON'
{
  "version": 1,
  "flags": [
    {
      "name": "NotSnake", "kind": "gate", "category": "feature",
      "binding": "compile", "effect": "toggle", "default": true, "seam": "x"
    }
  ]
}
JSON

expect_fail "wrong registry version" "version must be 1" <<'JSON'
{
  "version": 2,
  "flags": []
}
JSON

expect_fail "missing required top-level key" "missing required key \`flags\`" <<'JSON'
{
  "version": 1
}
JSON

echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "flag-registry validator OK (accepts valid registries, rejects each violation class)"
