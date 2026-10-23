#!/usr/bin/env bash
# Audit the Makefile contract implied by ffreis-platform-standards lefthook
# language remotes. This deliberately never invokes make: it is safe to run
# over a fleet before a standards-pin bump, and reports targets that would fail
# later at the complex/release promotion gate.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: audit-required-make-targets.sh REPOSITORY [REPOSITORY ...]

Inspect each repository's lefthook.yml. For every selected shared language
config, report Makefile targets used by its complex/release tiers that are
missing locally. Exit 1 when a selected config is incomplete, 0 otherwise.

Only remotes from ffreis-platform-standards are considered. The required
targets are derived from this checkout's lefthook/*.yml files, so audit the
standards revision you intend to pin.
EOF
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  [[ $# -eq 0 ]] && exit 2
  exit 0
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
standards_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
status=0

required_targets() {
  local config=$1
  awk '
    /^[^[:space:]]/ { tier = 0 }
    /^(complex|release):[[:space:]]*$/ { tier = 1; next }
    tier && /^[[:space:]]*run:[[:space:]]*make[[:space:]]+[[:alnum:]_.%\/-]+/ {
      line = $0
      sub(/^[[:space:]]*run:[[:space:]]*make[[:space:]]+/, "", line)
      split(line, words, /[[:space:]]+/)
      print words[1]
    }
  ' "$standards_root/$config" | sort -u
}

make_targets() {
  local makefile=$1
  # A target may share its rule with other targets. This intentionally models
  # declarations only (rather than `make -n`), keeping the audit non-mutating.
  awk '
    /^[[:alnum:]_.%\/-]+([[:space:]]+[[:alnum:]_.%\/-]+)*[[:space:]]*:/ {
      line = $0
      sub(/:.*/, "", line)
      count = split(line, names, /[[:space:]]+/)
      for (i = 1; i <= count; i++) print names[i]
    }
  ' "$makefile" | sort -u
}

for repo in "$@"; do
  if [[ ! -d $repo ]]; then
    printf 'ERROR %s: directory does not exist\n' "$repo" >&2
    status=1
    continue
  fi

  hook_file="$repo/lefthook.yml"
  if [[ ! -f $hook_file ]]; then
    printf 'SKIP  %s: no lefthook.yml\n' "$repo"
    continue
  fi
  if ! grep -Eq 'git_url:.*ffreis-platform-standards' "$hook_file"; then
    printf 'SKIP  %s: does not consume ffreis-platform-standards\n' "$repo"
    continue
  fi

  mapfile -t configs < <(
    grep -Eo 'lefthook/(go|python|rust|terraform|ansible|kotlin|swift)\.yml' "$hook_file" \
      | sort -u
  )
  if [[ ${#configs[@]} -eq 0 ]]; then
    printf 'SKIP  %s: standards remote has no language config\n' "$repo"
    continue
  fi

  if [[ ! -f $repo/Makefile ]]; then
    printf 'FAIL  %s: selected %s but has no Makefile\n' "$repo" "${configs[*]}" >&2
    status=1
    continue
  fi

  mapfile -t declared < <(make_targets "$repo/Makefile")
  missing=()
  for config in "${configs[@]}"; do
    while IFS= read -r target; do
      [[ -z $target ]] && continue
      if ! printf '%s\n' "${declared[@]}" | grep -Fxq "$target"; then
        missing+=("$config:$target")
      fi
    done < <(required_targets "$config")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    printf 'PASS  %s: %s complex/release Makefile contract complete\n' "$repo" "${configs[*]}"
  else
    printf 'FAIL  %s: missing %s\n' "$repo" "${missing[*]}" >&2
    status=1
  fi
done

exit "$status"
