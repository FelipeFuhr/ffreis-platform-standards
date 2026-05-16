#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

max_bytes="${MAX_BYTES:-1048576}" # 1 MiB

while IFS= read -r -d '' file; do
  # Only consider paths that are regular files in the staging area
  if [[ ! -f "$file" ]]; then
    continue
  fi
  size="$(wc -c <"$file" | tr -d ' ')"
  if [[ "$size" -gt "$max_bytes" ]]; then
    echo "ERROR: large file detected: $file ($size bytes > $max_bytes bytes)"
    exit 1
  fi
done < <(git diff --cached --name-only -z --diff-filter=ACM)

return 0
