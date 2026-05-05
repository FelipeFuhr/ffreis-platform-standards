#!/usr/bin/env bash
set -euo pipefail
while IFS= read -r file; do
  [ -f "$file" ] || continue
  file "$file" | grep -q 'binary' && { echo "binary file staged: $file" >&2; exit 1; }
done < <(git diff --cached --name-only)
