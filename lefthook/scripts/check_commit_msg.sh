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

if ! printf '%s' "$msg" | rg -q '^(feat|fix|docs|chore|refactor|test|ci|build)(\([a-z0-9_-]+\))?: '; then
  echo "ERROR: commit message must follow Conventional Commits." >&2
  echo "Example: feat(cli): add dry-run flag" >&2
  exit 1
fi
