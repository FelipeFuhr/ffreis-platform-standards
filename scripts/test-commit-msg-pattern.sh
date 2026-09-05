#!/usr/bin/env bash
# Test the conventional-commits pattern that lefthook/base.yml actually ships.
#
# The pattern is EXTRACTED from lefthook/base.yml rather than duplicated here.
# A copy would let the two drift and still pass — the point of this script is to
# exercise the artifact as consumers receive it, so if the extraction fails the
# script errors out instead of quietly testing a stale literal.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base_yml="$repo_root/lefthook/base.yml"

[ -f "$base_yml" ] || { echo "FAIL: $base_yml not found" >&2; exit 1; }

# The single `pattern='...'` line inside the conventional-commits hook.
pattern=$(sed -n "s/^[[:space:]]*pattern='\(.*\)'[[:space:]]*$/\1/p" "$base_yml")

if [ -z "$pattern" ]; then
  echo "FAIL: could not extract the commit-msg pattern from lefthook/base.yml." >&2
  echo "      The hook was probably restructured — update this extractor." >&2
  exit 1
fi
if [ "$(printf '%s\n' "$pattern" | wc -l)" -ne 1 ]; then
  echo "FAIL: extracted more than one pattern; the extractor is ambiguous." >&2
  exit 1
fi

echo "pattern under test: $pattern"
echo

pass=0
fail=0

# accept <message>  — the hook must ALLOW this message
accept() {
  if printf '%s' "$1" | grep -qE "$pattern"; then
    printf '  ok    accept  %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  FAIL  accept  %s  (was rejected)\n' "$1"; fail=$((fail + 1))
  fi
}

# reject <message>  — the hook must REJECT this message
reject() {
  if printf '%s' "$1" | grep -qE "$pattern"; then
    printf '  FAIL  reject  %s  (was accepted)\n' "$1"; fail=$((fail + 1))
  else
    printf '  ok    reject  %s\n' "$1"; pass=$((pass + 1))
  fi
}

echo "-- breaking-change marker (Conventional Commits 1.0.0) --"
accept 'feat!: drop support for node 12'
accept 'feat(bedrock)!: multimodal ConversationMessage'
accept 'fix(api)!: rename the response field'
accept 'refactor!: collapse the adapter layer'

echo
echo "-- plain and scoped forms --"
accept 'feat: add a thing'
accept 'fix(scope): correct a thing'
accept 'chore(deps-dev): bump a pinned action'
accept 'ci: route to the self-hosted runner'
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

echo
accept "feat: $(printf 'x%.0s' $(seq 1 100))"   # exactly 100 chars, at the cap

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
echo "commit-msg pattern OK"
