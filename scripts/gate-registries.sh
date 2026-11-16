#!/usr/bin/env bash
# Validate whichever declarative registries a repo owns, against the fleet
# schemas at a pinned commit of this repo.
#
# WHY THIS EXISTS
# ---------------
# The first two consumers of the metric registry each grew their own Makefile
# target: four variables, a cached-download rule and a run line, hand-copied.
# Wiring the FLAG registry's gate into three more repos would have made five
# copies of the same twelve lines, diverging the moment one of them learned
# something (a second file to fetch, a cache path, an offline fallback). The
# flag validator needs three files where the metric one needs two, so the
# copies had already started to differ.
#
# So a consumer wires ONE line instead:
#
#   STANDARDS_CACHE ?= $(HOME)/.cache/ffreis-standards/$(STANDARDS_SHA)
#   validate-registries:
#       @bash $(STANDARDS_CACHE)/gate-registries.sh "$(STANDARDS_SHA)"
#
# Nothing lands in the repo: see the CACHE note below for why that is a
# correctness property and not tidiness.
#
# and the next registry kind extends this script rather than every Makefile in
# the fleet.
#
# WHAT IT DOES NOT DO
# -------------------
# It does not fail a repo that owns no registry. A gate that cannot be wired
# unconditionally gets wired selectively, and then the repo that most needs it
# is the one nobody remembers to wire. "No registry here" is a clean exit with
# a line saying so — the fleet auditor's `flag-seams`/`metric-seams` findings
# are what argue a repo SHOULD own one; that is not this script's job.
#
# Usage: gate-registries.sh <standards-sha> [repo-dir]
# Exit:  0 all present registries valid (or none present) · 1 findings
#        · 2 usage, or a tool that could not be fetched
set -uo pipefail

SHA="${1:-}"
REPO="${2:-$PWD}"
RAW="${PLATFORM_STANDARDS_RAW:-https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards}"

if [[ -z "$SHA" ]]; then
  echo "usage: gate-registries.sh <standards-sha> [repo-dir]" >&2
  exit 2
fi
# A branch name or tag would make the gate's verdict change under a repo
# without its diff changing, which is the opposite of a pin.
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "gate-registries: <standards-sha> must be a full 40-char commit sha, got '$SHA'" >&2
  echo "                 a tag or branch is not a pin: the gate's verdict would move on its own" >&2
  exit 2
fi

cd "$REPO" || exit 2

# The cache lives OUTSIDE the repo, and that is not a preference.
#
# It was `.bin/standards-$SHA` inside the consumer. Rolling that out to the
# third repo, its markdownlint walked the cached `quality-rules.md` and failed
# the build on the STANDARDS repo's table style — `.bin/` is gitignored, and
# markdownlint does not consult gitignore. A fetched tool is not the repo's
# content, and every linter, formatter, coverage walker and dead-code scanner
# in the fleet has to be told that separately if it sits in the tree. So it
# does not sit in the tree.
#
# Keyed by sha, so two pins coexist and a bump is a fresh directory rather than
# a mutated one.
CACHE="${FFREIS_STANDARDS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ffreis-standards/$SHA}"
mkdir -p "$CACHE" || exit 2

# fetch <path-in-standards-repo> — cached; a present file is never re-fetched,
# so a second run needs no network and a sandboxed CI job works offline once
# warmed.
fetch() {
  local path="$1" dest
  dest="$CACHE/$(basename "$path")"
  if [[ -s "$dest" ]]; then
    printf '%s' "$dest"
    return 0
  fi
  if ! curl -fsSL "$RAW/$SHA/$path" -o "$dest" 2>/dev/null; then
    rm -f "$dest"
    return 1
  fi
  # An HTML error page is 200 OK and non-empty. Without this check a renamed
  # script would be "fetched" and then fail as a syntax error, which reads as
  # a broken registry rather than a broken pin.
  if [[ "$(head -c 1 "$dest")" == "<" ]]; then
    rm -f "$dest"
    return 1
  fi
  printf '%s' "$dest"
}

cannot_fetch() {
  echo "gate-registries: cannot fetch $1 from $RAW/$SHA" >&2
  echo "                 check the pin, or the network" >&2
  exit 2
}

status=0
found=0

if [[ -f flags/flags.json ]]; then
  found=1
  validator=$(fetch scripts/validate-flag-registry.py) || cannot_fetch scripts/validate-flag-registry.py
  schema=$(fetch flags/flag-registry.schema.json) || cannot_fetch flags/flag-registry.schema.json
  vocabulary=$(fetch flags/quality-rules.md) || cannot_fetch flags/quality-rules.md
  python3 "$validator" --schema "$schema" --vocabulary "$vocabulary" flags/flags.json || status=1
fi

if [[ -f metrics/metrics.json ]]; then
  found=1
  validator=$(fetch scripts/validate-metric-registry.py) || cannot_fetch scripts/validate-metric-registry.py
  schema=$(fetch metrics/metric-registry.schema.json) || cannot_fetch metrics/metric-registry.schema.json
  python3 "$validator" --schema "$schema" metrics/metrics.json || status=1
fi

if [[ "$found" -eq 0 ]]; then
  echo "  --   no flags/flags.json or metrics/metrics.json here — nothing to validate."
  echo "       (whether this repo SHOULD declare one is audit-repo-standards.sh's question)"
fi

exit "$status"
