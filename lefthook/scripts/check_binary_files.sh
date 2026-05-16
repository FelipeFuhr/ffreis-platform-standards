#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

while IFS= read -r -d '' file; do
  if [[ -f "$file" ]] && file --mime "$file" | rg -q 'charset=binary'; then
    echo "ERROR: binary file detected: $file"
    exit 1
  fi
done < <(git diff --cached --name-only -z --diff-filter=AM)

return 0
