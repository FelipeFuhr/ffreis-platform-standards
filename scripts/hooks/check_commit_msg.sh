#!/usr/bin/env bash
set -euo pipefail
msg=$(cat "$1")
pattern='^(feat|fix|docs|chore|refactor|test|ci|perf|style|build|revert)(\([a-z0-9-]+\))?: .{1,100}$'
echo "$msg" | grep -qE "$pattern" || { echo "non-conventional commit message: $msg" >&2; exit 1; }
