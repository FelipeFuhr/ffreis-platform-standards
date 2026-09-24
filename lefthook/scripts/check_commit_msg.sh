#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

msg_file="${1:-}"

if [[ -z "$msg_file" || ! -f "$msg_file" ]]; then
  echo "ERROR: commit message file not provided" >&2
  exit 1
fi


if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: This hook requires 'rg' (ripgrep) to be installed and available on PATH." >&2
  echo "Install ripgrep from https://github.com/BurntSushi/ripgrep#installation or via your package manager (e.g., 'brew install ripgrep', 'apt install ripgrep')." >&2
  exit 1
fi

msg="$(cat "$msg_file")"

# Very small conventional-commit guard to keep public repos tidy.
#
# Keep `pattern` in sync with lefthook/base.yml's inline `conventional-commits`
# command (this script is distributed standalone to repos that pull it
# directly, instead of consuming base.yml's command) —
# scripts/test-commit-msg-pattern.sh extracts both this line and base.yml's
# and asserts they accept/reject the same example messages, so neither file
# keeps its own copy of the truth.
pattern='^(feat|fix|docs|chore|refactor|test|ci|perf|style|build|revert)(\([a-z0-9-]+\))?!?: .{1,100}$'
# Looser than `pattern`: same type list, but any non-empty scope body and no
# length cap. If a message matches `loose_pattern` but not `pattern`, the
# type/shape is fine and the real problem is the scope charset or the
# description length — say so instead of the generic Conventional Commits
# message, which reads as a type problem.
loose_pattern='^(feat|fix|docs|chore|refactor|test|ci|perf|style|build|revert)(\(.+\))?!?: .*$'

if ! printf '%s' "$msg" | rg -q "$pattern"; then
  if printf '%s' "$msg" | rg -q "$loose_pattern"; then
    echo "ERROR: type looks right — check scope (lowercase/digits/hyphens only, no underscores/spaces/caps) or description length (1-100 chars)." >&2
  else
    echo "ERROR: commit message must follow Conventional Commits." >&2
    echo "Example: feat(cli): add dry-run flag" >&2
    echo "Types: feat fix docs chore refactor test ci perf style build revert" >&2
  fi
  exit 1
fi
