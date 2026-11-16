#!/usr/bin/env bash
# Behaviour lock for scripts/gate-registries.sh.
#
# The cases that matter are the ones where a gate could pass without gating:
# a repo with no registry, an unreachable pin, and a pin that 404s. Each of
# those is a way this script could report success while validating nothing —
# the exact failure the registries exist to prevent, one level up.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/gate-registries.sh"
SHA=45f723aab970e319e1aa1c37482b3a777f7531d7
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Every case gets its OWN cache directory, and none of them get the
# developer's real one.
#
# When the cache moved out of the consumer repo it became keyed by sha alone,
# so the fixtures started sharing it — and the "an unreachable standards host
# must exit 2" case began passing because an earlier case had already warmed
# the tools. A test that cannot fail is the thing this whole script exists to
# prevent; it must not be reintroduced here.
cache_for() { # cache_for <name> -> a fresh, empty cache path
  local dir="$TMP/cache-$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

pass=0
fail=0

check() { # check <want-exit> <label> <dir> [env-prefix...]
  local want="$1" label="$2" dir="$3"; shift 3
  local out got
  out="$(env "FFREIS_STANDARDS_CACHE=$(cache_for "$(basename "$dir")")" "$@" \
    bash "$GATE" "$SHA" "$dir" 2>&1)"; got=$?
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     wanted exit %s, got %s\n     %s\n' "$label" "$want" "$got" "$out"
  fi
}

check_text() { # check_text <label> <needle> <dir>
  local label="$1" needle="$2" dir="$3"
  local out
  out="$(FFREIS_STANDARDS_CACHE="$(cache_for "text-$(basename "$dir")")" \
    bash "$GATE" "$SHA" "$dir" 2>&1)"
  if grep -qF -- "$needle" <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     output lacked: %s\n     %s\n' "$label" "$needle" "$out"
  fi
}

valid_flag='{"version":1,"flags":[{"name":"source","kind":"adapter","category":"data",
  "binding":"runtime","effect":"route","options":["mock","live"],"default":"mock",
  "seam":"store::dispatch","description":"Where records come from in this test fixture."}]}'
valid_metric='{"version":1,"project":"t","metrics":[{"name":"a","title":"A","kind":"count",
  "surface":"s","population":"all-traffic","source":{"signal":"x"},
  "exceptions":[{"scope":"coverage","reason":"a fixture has no scenario corpus behind it"}]}]}'

mk() { # mk <name> ; writes $TMP/<name> and echoes the path
  mkdir -p "$TMP/$1"; printf '%s' "$TMP/$1"
}

# --- nothing to validate is a clean exit, not a pass-by-accident ------------
empty=$(mk empty)
check 0 "a repo with no registry exits clean" "$empty"
check_text "and says what it did not find" "nothing to validate" "$empty"

# --- the happy paths --------------------------------------------------------
onlyflags=$(mk onlyflags); mkdir -p "$onlyflags/flags"
printf '%s' "$valid_flag" > "$onlyflags/flags/flags.json"
check 0 "a valid flag registry alone passes" "$onlyflags"

onlymetrics=$(mk onlymetrics); mkdir -p "$onlymetrics/metrics"
printf '%s' "$valid_metric" > "$onlymetrics/metrics/metrics.json"
check 0 "a valid metric registry alone passes" "$onlymetrics"

both=$(mk both); mkdir -p "$both/flags" "$both/metrics"
printf '%s' "$valid_flag" > "$both/flags/flags.json"
printf '%s' "$valid_metric" > "$both/metrics/metrics.json"
check 0 "both valid registries pass" "$both"
check_text "and both are reported" "metrics/metrics.json" "$both"

# --- each registry can fail independently -----------------------------------
badflags=$(mk badflags); mkdir -p "$badflags/flags" "$badflags/metrics"
printf '{"version":1,"flags":[{"name":"x"}]}' > "$badflags/flags/flags.json"
printf '%s' "$valid_metric" > "$badflags/metrics/metrics.json"
check 1 "an invalid flag registry fails even beside a valid metric one" "$badflags"

badmetrics=$(mk badmetrics); mkdir -p "$badmetrics/flags" "$badmetrics/metrics"
printf '%s' "$valid_flag" > "$badmetrics/flags/flags.json"
printf '{"version":1,"metrics":[{"name":"a"}]}' > "$badmetrics/metrics/metrics.json"
check 1 "an invalid metric registry fails even beside a valid flag one" "$badmetrics"

# A failing FIRST registry must not stop the second from being checked, or a
# repo would fix one finding at a time with no idea how many remain.
check_text "a failure in the first registry still reports the second" "metrics/metrics.json" "$badflags"

# --- a pin that is not a pin -------------------------------------------------
pinned=$(mk pinned); mkdir -p "$pinned/flags"
printf '%s' "$valid_flag" > "$pinned/flags/flags.json"
for notasha in main v1.12.0 45f723a ""; do
  out="$(FFREIS_STANDARDS_CACHE="$(cache_for pin)" bash "$GATE" "$notasha" "$pinned" 2>&1)"; got=$?
  if [[ "$got" == 2 ]]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL a non-sha pin (%s) must exit 2, got %s\n' "${notasha:-<empty>}" "$got"
  fi
done

# --- an unfetchable tool is exit 2, never a pass -----------------------------
# The sharpest case: if a bad pin reported success, every repo would gate
# against nothing the moment the standards repo moved a file.
nocache=$(mk nocache); mkdir -p "$nocache/flags"
printf '%s' "$valid_flag" > "$nocache/flags/flags.json"
# A COLD cache is the whole point of this case: with a warm one, exit 0 is
# correct behaviour and the assertion below would be vacuous.
out="$(FFREIS_STANDARDS_CACHE="$(cache_for cold)" \
  PLATFORM_STANDARDS_RAW=https://127.0.0.1:1 bash "$GATE" "$SHA" "$nocache" 2>&1)"; got=$?
if [[ "$got" == 2 ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL an unreachable standards host must exit 2 on a COLD cache, got %s\n     %s\n' "$got" "$out"
fi

# --- and once warmed, it needs no network ------------------------------------
# This is what lets the gate run in a sandboxed CI job and on a plane.
warm=$(mk warm); mkdir -p "$warm/flags"
printf '%s' "$valid_flag" > "$warm/flags/flags.json"
warmcache="$(cache_for warm)"
FFREIS_STANDARDS_CACHE="$warmcache" bash "$GATE" "$SHA" "$warm" >/dev/null 2>&1
out="$(FFREIS_STANDARDS_CACHE="$warmcache" \
  PLATFORM_STANDARDS_RAW=https://127.0.0.1:1 bash "$GATE" "$SHA" "$warm" 2>&1)"; got=$?
if [[ "$got" == 0 ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL a warmed cache must work offline, got %s\n     %s\n' "$got" "$out"
fi

printf '\ngate-registries selftest: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
