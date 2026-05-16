#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: ripgrep (rg) is required by scripts/hooks/check_merge_markers.sh but is not installed." >&2
  echo "Please install ripgrep (rg) and re-run this hook." >&2
  exit 1
fi

if rg -n --hidden --glob '!.git/**' '^(<{7}|={7}|>{7})' . >/dev/null; then
  echo "ERROR: merge conflict markers found" >&2
  rg -n --hidden --glob '!.git/**' '^(<{7}|={7}|>{7})' .
  exit 1
fi
