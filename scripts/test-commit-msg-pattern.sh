#!/usr/bin/env bash
# Test the conventional-commits patterns shipped in TWO places:
#   - lefthook/base.yml's inline `conventional-commits` command
#   - lefthook/scripts/check_commit_msg.sh (distributed standalone to repos
#     that pull it directly instead of consuming base.yml)
#
# Both patterns are EXTRACTED from their source files rather than duplicated
# here. A copy would let the two files drift and still pass — the point of
# this script is to exercise the artifacts as consumers actually receive
# them, so if an extraction fails the script errors out instead of quietly
# testing a stale literal.
#
# Every example message below is run through BOTH extracted patterns and
# must produce the SAME accept/reject verdict from each. This is the guard
# against silent drift: base.yml and check_commit_msg.sh once disagreed on
# whether a scope could contain `_` (only base.yml's did not), on the
# perf/style/revert types, and on the `!` breaking-change marker — and
# nothing asserted the two matched, so the mismatch shipped for a long time.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base_yml="$repo_root/lefthook/base.yml"
check_script="$repo_root/lefthook/scripts/check_commit_msg.sh"

[ -f "$base_yml" ] || { echo "FAIL: $base_yml not found" >&2; exit 1; }
[ -f "$check_script" ] || { echo "FAIL: $check_script not found" >&2; exit 1; }

# extract_var <file> <var-name> — pulls the single `<var-name>='...'` line.
extract_var() {
  local file="$1" var="$2"
  sed -n "s/^[[:space:]]*${var}='\\(.*\\)'[[:space:]]*\$/\\1/p" "$file"
}

assert_single_line() {
  local label="$1" value="$2"
  if [ -z "$value" ]; then
    echo "FAIL: could not extract $label. The hook was probably restructured — update this extractor." >&2
    exit 1
  fi
  if [ "$(printf '%s\n' "$value" | wc -l)" -ne 1 ]; then
    echo "FAIL: extracted more than one candidate for $label; the extractor is ambiguous." >&2
    exit 1
  fi
}

base_pattern=$(extract_var "$base_yml" "pattern")
base_loose=$(extract_var "$base_yml" "loose_pattern")
script_pattern=$(extract_var "$check_script" "pattern")
script_loose=$(extract_var "$check_script" "loose_pattern")

assert_single_line "base.yml pattern" "$base_pattern"
assert_single_line "base.yml loose_pattern" "$base_loose"
assert_single_line "check_commit_msg.sh pattern" "$script_pattern"
assert_single_line "check_commit_msg.sh loose_pattern" "$script_loose"

echo "base.yml            pattern: $base_pattern"
echo "check_commit_msg.sh pattern: $script_pattern"
echo

pass=0
fail=0

# verdict <pattern> <message>  — 0 if the pattern accepts the message
verdict() {
  printf '%s' "$2" | grep -qE "$1"
}

# check <label> <pattern> <expect: accept|reject> <message>
check() {
  local label="$1" pattern="$2" expect="$3" msg="$4"
  local matched=1
  verdict "$pattern" "$msg" && matched=0
  if [ "$expect" = "accept" ]; then
    if [ "$matched" -eq 0 ]; then
      printf '  ok    %-20s accept  %s\n' "$label" "$msg"; pass=$((pass + 1))
    else
      printf '  FAIL  %-20s accept  %s  (was rejected)\n' "$label" "$msg"; fail=$((fail + 1))
    fi
  else
    if [ "$matched" -ne 0 ]; then
      printf '  ok    %-20s reject  %s\n' "$label" "$msg"; pass=$((pass + 1))
    else
      printf '  FAIL  %-20s reject  %s  (was accepted)\n' "$label" "$msg"; fail=$((fail + 1))
    fi
  fi
}

# accept/reject <message> — run the SAME message through both files' strict
# patterns; any drift between base.yml and check_commit_msg.sh trips this.
accept() {
  check "base.yml" "$base_pattern" accept "$1"
  check "check_commit_msg.sh" "$script_pattern" accept "$1"
}
reject() {
  check "base.yml" "$base_pattern" reject "$1"
  check "check_commit_msg.sh" "$script_pattern" reject "$1"
}

echo "-- breaking-change marker (Conventional Commits 1.0.0) --"
accept 'feat!: drop support for node 12'
accept 'feat(bedrock)!: multimodal ConversationMessage'
accept 'fix(api)!: rename the response field'
accept 'refactor!: collapse the adapter layer'

echo
echo "-- plain and scoped forms, full type list --"
accept 'feat: add a thing'
accept 'fix(scope): correct a thing'
accept 'chore(deps-dev): bump a pinned action'
accept 'ci: route to the self-hosted runner'
accept 'perf: reduce allocation churn'
accept 'style(lint): reformat imports'
accept 'revert: undo the previous change'

echo
echo "-- still rejected --"
reject 'nope: not a real type'
reject 'feat add a thing'                    # missing colon
reject 'feat:no space after colon'
reject 'feat(Scope): uppercase scope'
reject 'feat(scope)!!: doubled marker'
reject '!feat: marker in the wrong place'
reject 'feat!(scope): marker before the scope'
reject 'feat: '                              # empty description
reject ''
reject "feat: $(printf 'x%.0s' $(seq 1 101))"   # 101-char description, over the cap
# The exact real-world friction case this suite exists to catch: a
# snake_case scope (ffreis-home-infra's ansible roles `os_setup`,
# `cache_tier`) must be rejected by BOTH files identically — this is the
# underscore-in-scope drift that once let the same commit pass in one repo
# and fail in another depending on which checker it happened to route through.
reject 'feat(os_setup): use snake_case scope'

echo
accept "feat: $(printf 'x%.0s' $(seq 1 100))"   # exactly 100 chars, at the cap

echo
echo "-- loose_pattern extraction (used by the type-looks-right diagnostic) --"
# Not exhaustive re-testing of the diagnostic's error text (that's exercised
# by running the real script below) — just confirms both loose patterns
# agree with the strict ones on the discriminating cases: a message that
# fails strict-but-not-loose should be diagnosed as a scope/length problem,
# and both files must agree on which bucket a message falls into.
for msg in 'feat(os_setup): use snake_case scope' "feat: $(printf 'x%.0s' $(seq 1 101))" 'nope: not a real type' 'feat add a thing'; do
  base_loose_ok=1; verdict "$base_loose" "$msg" && base_loose_ok=0
  script_loose_ok=1; verdict "$script_loose" "$msg" && script_loose_ok=0
  if [ "$base_loose_ok" -eq "$script_loose_ok" ]; then
    printf '  ok    loose-agree          %s\n' "$msg"; pass=$((pass + 1))
  else
    printf '  FAIL  loose-agree          %s  (base=%s script=%s)\n' "$msg" "$base_loose_ok" "$script_loose_ok"; fail=$((fail + 1))
  fi
done

echo
echo "-- check_commit_msg.sh diagnostic text, run as the real script --"
if ! command -v rg >/dev/null 2>&1; then
  # check_commit_msg.sh hard-requires rg at consumer commit-time (unrelated to
  # this test) — this repo's own CI runner doesn't provision it, so skip this
  # real-script confirmation here rather than failing the gate on missing
  # infrastructure. The loose_pattern cross-check above already verifies the
  # underlying accept/reject logic tool-independently via grep -E; this block
  # only adds confirmation of the actual stderr wording where rg is available
  # (e.g. local dev machines, which already need rg to use this hook at all).
  echo "  skip  rg not installed — see comment above"
else
  tmp_msg=$(mktemp)
  trap 'rm -f "$tmp_msg"' EXIT

  assert_stderr_contains() {
    local desc="$1" msg="$2" needle="$3"
    printf '%s\n' "$msg" > "$tmp_msg"
    local out
    if out=$(bash "$check_script" "$tmp_msg" 2>&1 >/dev/null); then
      printf '  FAIL  %-20s %s  (script accepted, expected rejection)\n' "$desc" "$msg"; fail=$((fail + 1))
      return
    fi
    if printf '%s' "$out" | grep -qF "$needle"; then
      printf '  ok    %-20s %s\n' "$desc" "$msg"; pass=$((pass + 1))
    else
      printf '  FAIL  %-20s %s  (missing hint: %s)\n' "$desc" "$msg" "$needle"; fail=$((fail + 1))
      printf '        got: %s\n' "$out"
    fi
  }

  assert_stderr_contains "scope-not-type-hint" 'feat(os_setup): use snake_case scope' "type looks right"
  assert_stderr_contains "generic-type-hint" 'nope: not a real type' "Conventional Commits"
fi

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
echo "commit-msg patterns OK (base.yml and check_commit_msg.sh agree)"
