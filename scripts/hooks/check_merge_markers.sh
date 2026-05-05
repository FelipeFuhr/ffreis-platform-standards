#!/usr/bin/env bash
set -euo pipefail
files=$(git diff --cached --name-only)
[ -z "$files" ] && exit 0
bad=$(echo "$files" | xargs grep -l '^<<<<<<< \|^=======$\|^>>>>>>> ' 2>/dev/null || true)
[ -n "$bad" ] && { echo "merge markers in: $bad" >&2; exit 1; }
