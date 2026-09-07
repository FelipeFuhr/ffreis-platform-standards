#!/usr/bin/env bash
# mutation-diff.sh — run cargo-mutants against ONLY the lines this branch
# changed, then score the result with scripts/mutation_score.sh.
#
# WHY THIS EXISTS: the lefthook `release` tier fires on any branch whose
# conventional commits imply a minor/major bump — i.e. every `feat:` branch.
# It used to run `make mutation`, an UNSCOPED whole-crate sweep. On
# ffreis-urbs-admin that is 1,606 mutants at ~44s each — ~19 hours against a
# ~50 minute promotion budget, so the gate was killed every time and no `feat:`
# PR could be promoted. That is a property of crate SIZE, not of any one
# branch: every Rust repo hits it once it grows.
#
# Scoped to the branch's own diff the same repo measured 88 mutants in ~20 min
# and surfaced ten real gaps, one of them in the domain model. It is also the
# better MEASURE: a whole-crate score is dominated by code the PR never
# touched, which is how a mutation gate reports a high number while saying
# nothing about the change under review.
#
# Division of labour, fleet-wide:
#   make mutation-diff  -> THIS script. PR-time gate (lefthook `release` tier,
#                          /ready). Diff-scoped, minutes.
#   make mutation       -> whole-crate sweep. Scheduled CI (rust-mutation.yml
#                          on a cron) and on-demand. Hours; never a PR gate.
#
# Usage: mutation-diff.sh <threshold-percent> [cargo-mutants args...]
#   e.g. mutation-diff.sh 70 --minimum-test-timeout 60 --all-features -p my-crate
#
# Env:
#   MUTATION_BASE_REF   base to diff against (default: origin/HEAD, else
#                       origin/main, else main)
#   MUTANTS_TMPDIR      parent for this run's scratch (default: the workspace
#                       cache tier if configured, else $TMPDIR, else /tmp)
#   MUTATION_JOBS       parallel mutants (default: auto, from free RAM + CPUs).
#                       Ignored if the caller already passed -j/--jobs.
#
# Exit: 0 pass (or nothing to mutate); 1 below threshold / harness failure;
#       2 usage error.

set -euo pipefail

threshold="${1:-}"
if [[ -z "$threshold" ]]; then
  echo "usage: $(basename "$0") <threshold-percent> [cargo-mutants args...]" >&2
  exit 2
fi
shift

# The SOURCE dir is the cwd (repos whose crate lives in a subdirectory call
# this as `cd lambdas && bash ../scripts/mutation-diff.sh`); the REPO root is
# only used for the "scratch must not be inside the repo" guard below.
src_dir="$(pwd -P)"
repo_root="$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# 1. Resolve the base ref to diff against.
# ---------------------------------------------------------------------------
base="${MUTATION_BASE_REF:-}"
if [[ -z "$base" ]]; then
  base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
fi
if [[ -z "$base" ]]; then
  for candidate in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      base="$candidate"
      break
    fi
  done
fi
if [[ -z "$base" ]] || ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
  echo "ERROR: cannot resolve a base ref to diff against (tried MUTATION_BASE_REF," >&2
  echo "       origin/HEAD, origin/main, origin/master, main, master). A shallow" >&2
  echo "       clone with no base ref cannot be diff-scoped — fetch the base or" >&2
  echo "       set MUTATION_BASE_REF." >&2
  exit 1
fi

merge_base="$(git merge-base "$base" HEAD 2>/dev/null || true)"
if [[ -z "$merge_base" ]]; then
  echo "ERROR: no merge-base between '$base' and HEAD — refusing to guess a diff." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Scratch root. Two traps live here, both learned the hard way.
#
#    (a) cargo-mutants ignores CARGO_TARGET_DIR for its per-mutant scratch
#        copies — it copies the source tree under $TMPDIR instead. Left at the
#        default that is /tmp on the ROOT filesystem, where abandoned runs have
#        filled the disk to zero and crashed sessions. So we place it
#        deliberately and remove it on exit.
#
#    (b) the scratch root must NEVER be inside the repo: cargo-mutants copies
#        the working tree wholesale, so a scratch dir inside it copies its own
#        previous copy, recursively, until the path exceeds the OS limit.
#        Checked below rather than merely documented.
# ---------------------------------------------------------------------------
tmp_parent="${MUTANTS_TMPDIR:-${FFREIS_CACHE_TIER:+$FFREIS_CACHE_TIER/cargo-mutants}}"
tmp_parent="${tmp_parent:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_parent" 2>/dev/null || {
  echo "ERROR: cannot create scratch parent '$tmp_parent'." >&2
  exit 1
}
tmp_parent="$(cd "$tmp_parent" && pwd -P)"

case "$tmp_parent/" in
  "$repo_root"/*)
    echo "ERROR: mutation scratch dir '$tmp_parent' is INSIDE the repo ($repo_root)." >&2
    echo "       cargo-mutants copies the whole working tree, so it would copy its" >&2
    echo "       own scratch dir recursively until the path exceeds the OS limit." >&2
    echo "       Point MUTANTS_TMPDIR somewhere outside the repo." >&2
    exit 1
    ;;
esac

scratch="$(mktemp -d "$tmp_parent/mutation-diff.XXXXXX")"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 3. Compute the diff.
#
#    Two-dot against the MERGE-BASE, not three-dot against HEAD: cargo-mutants
#    requires the diff to apply cleanly to the tree on disk and aborts with
#    "Diff content doesn't match source file" otherwise. Diffing the merge-base
#    against the WORKING TREE matches what is actually there, so a dirty tree
#    (the normal local case — you are gating work you are about to commit)
#    still works. On a clean tree this is byte-identical to `base...HEAD`.
#
#    --relative does two jobs at once, both required when the crate lives in a
#    subdirectory (the rust-lambda layout, `cd lambdas && ...`): it drops
#    changes outside the source dir, and it rewrites the remaining paths
#    relative to it, so they match the tree cargo-mutants is actually looking
#    at. Without it every path would carry a `lambdas/` prefix that resolves to
#    nothing and the whole diff would silently match no files.
# ---------------------------------------------------------------------------
diff_file="$scratch/branch.diff"
git diff --relative "$merge_base" -- '*.rs' > "$diff_file"

if [[ ! -s "$diff_file" ]]; then
  echo "mutation-diff: no Rust changes against ${base} — nothing to mutate. PASS."
  exit 0
fi

changed_files="$(grep -c '^+++ ' "$diff_file" || true)"
echo "mutation-diff: mutating only lines changed against ${base} (${changed_files} .rs file(s))."

# ---------------------------------------------------------------------------
# 4. Run cargo-mutants.
#
#    CARGO_TARGET_DIR is deliberately UNSET for this run. This workspace's
#    cache-tier `cargo()` wrapper exports a shared per-checkout target dir, and
#    cargo-mutants passes its whole environment down to every mutant build — so
#    the mutants and the real working tree ended up in the SAME bucket, after
#    which the next `cargo test` in that tree silently reported a WRONG
#    assertion failure sourced from a mutated build. That is worse than a
#    broken build: it looks exactly like a real regression.
#
#    Unsetting it is not quite enough on this workspace, because ~/.cargo/bin/
#    cargo is itself a shim that RE-DERIVES a target dir under $CACHE_TIER when
#    the variable is empty. So CACHE_TIER is pointed into this run's scratch
#    too: the shim (and the equivalent bash function) then writes its per-copy
#    target dirs somewhere the EXIT trap actually removes, instead of leaking a
#    fresh multi-GB bucket onto the cache disk on every run. On a machine with
#    no such shim the variable is simply ignored and each scratch copy builds
#    into its own `target/` inside the copy — which the trap also removes.
#
#    The exit code is captured, not obeyed: cargo-mutants exits non-zero the
#    moment ANY mutant survives, which is far stricter than the fleet
#    threshold, and under `make` that would abort the recipe before the scorer
#    ever ran. mutation_score.sh owns the pass/fail decision — but the rc still
#    matters, because it is the only way to tell "ran, found nothing mutable"
#    (rc 0, no mutants.out — a genuine pass for an --in-diff run whose only .rs
#    changes were test files) from "died before writing anything" (rc != 0, no
#    mutants.out — a harness failure that must fail).
# ---------------------------------------------------------------------------
# --jobs. cargo-mutants defaults to ONE mutant at a time, and on a crate whose
# per-mutant cost is dominated by the rebuild that is the difference between a
# gate that fits the promotion budget and one that does not: this crate measured
# ~54s/mutant serially, i.e. ~82 min for a 91-mutant diff.
#
# The cap comes from real headroom, not from core count. Peak resident memory
# for one of these builds was measured at ~2.5 GB and is dominated by a
# per-crate baseline rather than being linear in job count, so RAM is the
# binding constraint and over-committing it does not fail as a build error —
# the OOM killer takes whatever it likes, on a box that is usually running
# several other sessions. Hence: ~3 GB reserved per job, never more than half
# the cores, and a hard ceiling of 4. An explicit MUTATION_JOBS always wins,
# and a -j/--jobs already in the caller's own args is left alone.
jobs_args=()
if ! printf '%s\n' "$@" | grep -qE '^(-j|--jobs)$'; then
  want="${MUTATION_JOBS:-auto}"
  if [[ "$want" == auto ]]; then
    avail_mib="$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null || echo 0)"
    cpus="$(nproc 2>/dev/null || echo 2)"
    by_mem=$(( avail_mib / 3000 ))
    by_cpu=$(( cpus / 2 ))
    want="$by_mem"
    [[ "$by_cpu" -lt "$want" ]] && want="$by_cpu"
    [[ "${MUTATION_JOBS_MAX:-4}" -lt "$want" ]] && want="${MUTATION_JOBS_MAX:-4}"
    [[ "$want" -lt 1 ]] && want=1
    echo "mutation-diff: --jobs ${want} (auto: ${avail_mib} MiB available, ${cpus} cpus)"
  fi
  jobs_args=(--jobs "$want")
fi

set +e
env -u CARGO_TARGET_DIR CACHE_TIER="$scratch/cargo-cache" TMPDIR="$scratch" \
  cargo mutants --in-diff "$diff_file" "${jobs_args[@]}" "$@" 2>&1
rc=$?
set -e
echo "mutation-diff: cargo-mutants exited ${rc}"

if [[ ! -d "$src_dir/mutants.out" ]]; then
  if [[ "$rc" -eq 0 ]]; then
    echo "mutation-diff: cargo-mutants found nothing mutable in this diff (e.g. only"
    echo "               test files changed). Nothing to score. PASS."
    exit 0
  fi
  echo "ERROR: cargo-mutants exited ${rc} and wrote no mutants.out/ — it died before" >&2
  echo "       producing any evidence. That is a harness failure, not a pass." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 5. Score. Same scorer, same contract, as the whole-crate `make mutation`.
# ---------------------------------------------------------------------------
score_sh="$(dirname "$0")/mutation_score.sh"
if [[ ! -f "$score_sh" ]]; then
  echo "ERROR: $score_sh not found — vendor it alongside this script." >&2
  exit 1
fi
bash "$score_sh" "$threshold" "$src_dir/mutants.out"
