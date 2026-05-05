#!/usr/bin/env bash
set -euo pipefail
MAX_KB=500
while IFS= read -r file; do
  [ -f "$file" ] || continue
  size=$(du -k "$file" | cut -f1)
  [ "$size" -gt "$MAX_KB" ] && { echo "large file ($size KB): $file" >&2; exit 1; }
done < <(git diff --cached --name-only)
