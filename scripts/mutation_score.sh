#!/usr/bin/env bash
# mutation_score.sh — score a completed cargo-mutants run against a threshold.
#
# WHY THIS EXISTS: `cargo mutants` exits non-zero if ANY mutant survives, so
# `make mutation` failed unconditionally regardless of the score — the local
# 'release' tier could never go green even on a run comfortably above the
# floor. CI never had that problem because rust-mutation.yml swallows the
# exit code and scores the outcome files instead. This script is that scorer,
# so the local gate and the CI gate can never disagree about what "passing"
# means.
#
# CANONICAL COPY. This file is the fleet source of truth (it began life in
# ffreis-job-arbiter and was promoted here). Repos VENDOR it at
# scripts/mutation_score.sh, the same way they vendor bootstrap_lefthook.sh —
# `make mutation` and `make mutation-diff` both call it, so the whole-crate and
# the diff-scoped gate can never disagree about what "passing" means. Fix bugs
# HERE and re-vendor; never fork a repo-local variant.
#
# CONTRACT (mirrors FelipeFuhr/ffreis-workflows-rust's rust-mutation.yml at
# aec226d / v2.0.1 — keep them in step):
#   - denominator is caught + missed; unviable (does not compile) and timeout
#     mutants are excluded, because no test could ever have caught them;
#   - a run that produced NO outcome files at all is a HARNESS FAILURE, not a
#     pass. Absence of evidence is not evidence of success — v2.0.1 added this
#     after the previous scorer reported a clean 100% for runs that had
#     measured nothing at all;
#   - real outcome files with zero viable mutants (e.g. an --in-diff run whose
#     diff touched no mutable code) IS a pass.
#
# Usage: mutation_score.sh <threshold-percent> [mutants-out-dir]

set -euo pipefail

threshold="${1:-}"
out_dir="${2:-mutants.out}"

if [[ -z "$threshold" ]]; then
  echo "usage: $(basename "$0") <threshold-percent> [mutants-out-dir]" >&2
  exit 2
fi

if [[ ! -d "$out_dir" ]]; then
  echo "ERROR: ${out_dir}/ does not exist — cargo-mutants wrote no outcomes." >&2
  echo "       That is a harness failure (wrong path, crashed run, bad args)," >&2
  echo "       not a passing run." >&2
  exit 1
fi

have_outcomes=0
for f in caught.txt missed.txt unviable.txt timeout.txt; do
  if [[ -f "${out_dir}/${f}" ]]; then
    have_outcomes=1
    break
  fi
done

if [[ "$have_outcomes" -eq 0 ]]; then
  echo "ERROR: no cargo-mutants outcome files (caught/missed/unviable/timeout.txt)" >&2
  echo "       under ${out_dir}/. Refusing to score a run that produced no evidence." >&2
  exit 1
fi

count_lines() {
  if [[ -f "$1" ]]; then
    # grep -c exits 1 on zero matches; that is a count, not an error.
    grep -c . "$1" 2>/dev/null || true
  else
    echo 0
  fi
}

caught=$(count_lines "${out_dir}/caught.txt")
missed=$(count_lines "${out_dir}/missed.txt")
timed_out=$(count_lines "${out_dir}/timeout.txt")
unviable=$(count_lines "${out_dir}/unviable.txt")

total=$((caught + missed))
echo "Caught: ${caught}  Missed: ${missed}  Timeout: ${timed_out}  Unviable: ${unviable}"

if [[ "$total" -eq 0 ]]; then
  echo "cargo-mutants ran and found no viable mutants (unviable: ${unviable}) — nothing to score."
  exit 0
fi

score=$((caught * 100 / total))
echo "Score: ${score}%  Threshold: ${threshold}%"

if [[ "$score" -lt "$threshold" ]]; then
  echo "Mutation score ${score}% is below threshold ${threshold}%." >&2
  exit 1
fi
