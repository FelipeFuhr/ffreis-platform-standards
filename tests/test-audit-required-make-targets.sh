#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
audit="$repo_root/scripts/audit-required-make-targets.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local name=$1
  local makefile=$2
  mkdir -p "$tmp/$name"
  printf '%s\n' \
    'remotes:' \
    '  - git_url: https://github.com/FelipeFuhr/ffreis-platform-standards' \
    '    ref: v1.10.0' \
    '    configs:' \
    '      - lefthook/rust.yml' > "$tmp/$name/lefthook.yml"
  printf '%s\n' "$makefile" > "$tmp/$name/Makefile"
}

make_repo complete 'lint test sec coverage-gate integration-coverage-gate build-release mutation:'
make_repo incomplete 'lint test sec coverage-gate integration-coverage-gate:'
mkdir -p "$tmp/python-incomplete"
printf '%s\n' \
  'remotes:' \
  '  - git_url: https://github.com/FelipeFuhr/ffreis-platform-standards' \
  '    ref: v1.10.0' \
  '    configs:' \
  '      - lefthook/python.yml' > "$tmp/python-incomplete/lefthook.yml"
printf '%s\n' 'lint coverage integration-coverage-gate:' > "$tmp/python-incomplete/Makefile"
mkdir -p "$tmp/no-standard"
printf '%s\n' 'remotes: []' > "$tmp/no-standard/lefthook.yml"

"$audit" "$tmp/complete" > "$tmp/complete.out"
grep -Fq 'PASS' "$tmp/complete.out"

if "$audit" "$tmp/incomplete" > "$tmp/incomplete.out" 2>&1; then
  echo 'expected missing Rust release targets to fail' >&2
  exit 1
fi
grep -Fq 'lefthook/rust.yml:build-release' "$tmp/incomplete.out"
grep -Fq 'lefthook/rust.yml:mutation' "$tmp/incomplete.out"

if "$audit" "$tmp/python-incomplete" > "$tmp/python-incomplete.out" 2>&1; then
  echo 'expected missing Python mutation target to fail' >&2
  exit 1
fi
grep -Fq 'lefthook/python.yml:mutation' "$tmp/python-incomplete.out"

"$audit" "$tmp/no-standard" > "$tmp/skip.out"
grep -Fq 'SKIP' "$tmp/skip.out"

echo 'audit-required-make-targets tests passed'
