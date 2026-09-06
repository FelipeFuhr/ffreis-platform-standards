#!/usr/bin/env bash
# mutation-diff-selftest.sh — behaviour lock for scripts/mutation-diff.sh.
#
# Runs hermetically: it builds throwaway git repos in $TMPDIR and puts a STUB
# `cargo` first on PATH, so nothing here compiles Rust or needs cargo-mutants
# installed. The stub is deliberately STRICTER than the real tool where it can
# be (it asserts on the environment it is handed), because a stub laxer than
# the real thing certifies bugs instead of catching them.
#
# Every case below fails if the corresponding guard in mutation-diff.sh is
# removed — that is the point of having them. Run: bash scripts/mutation-diff-selftest.sh

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
subject="$script_dir/mutation-diff.sh"
pass=0
fail=0

note() { printf '  %s\n' "$*"; }
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL  %s\n' "$1"; shift; for l in "$@"; do note "$l"; done; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Fixture: a git repo with `main` plus a branch that edits a Rust file.
#   make_repo <dir> <mode>     mode: rust | norust | subdir
# ---------------------------------------------------------------------------
make_repo() {
  local dir="$1" mode="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name test

  local src="$dir/src"
  [[ "$mode" == subdir ]] && src="$dir/crate/src"
  mkdir -p "$src"
  printf 'pub fn a() -> u8 { 1 }\n' > "$src/lib.rs"
  printf 'placeholder\n' > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "base"

  git -C "$dir" checkout -q -b feature
  if [[ "$mode" == norust ]]; then
    printf 'changed docs only\n' > "$dir/README.md"
  else
    printf 'pub fn a() -> u8 { 2 }\npub fn b() -> u8 { 3 }\n' > "$src/lib.rs"
  fi
  git -C "$dir" add -A
  git -C "$dir" commit -qm "feat: change"
}

# ---------------------------------------------------------------------------
# Stub cargo. Honours:
#   STUB_RC          exit code to return
#   STUB_CAUGHT/MISSED   write that many lines into mutants.out (absent = write none)
#   STUB_RECORD      file to append a report to (args + environment assertions)
# ---------------------------------------------------------------------------
make_stub() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/cargo" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${STUB_RECORD:-}" ]]; then
  {
    echo "ARGS: $*"
    echo "CARGO_TARGET_DIR: ${CARGO_TARGET_DIR-<unset>}"
    echo "TMPDIR: ${TMPDIR-<unset>}"
    echo "PWD: $PWD"
    # The diff handed to --in-diff is the contract with cargo-mutants; record it.
    for ((i = 1; i <= $#; i++)); do
      if [[ "${!i}" == "--in-diff" ]]; then
        j=$((i + 1)); echo "--- DIFF ---"; cat "${!j}"; echo "--- END DIFF ---"
      fi
    done
  } >> "$STUB_RECORD"
fi
if [[ -n "${STUB_CAUGHT:-}${STUB_MISSED:-}" ]]; then
  mkdir -p mutants.out
  : > mutants.out/caught.txt; : > mutants.out/missed.txt
  for ((n = 0; n < ${STUB_CAUGHT:-0}; n++)); do echo "caught $n" >> mutants.out/caught.txt; done
  for ((n = 0; n < ${STUB_MISSED:-0}; n++)); do echo "missed $n" >> mutants.out/missed.txt; done
fi
exit "${STUB_RC:-0}"
STUB
  chmod +x "$bin/cargo"
}

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
make_stub "$root/bin"
export PATH="$root/bin:$PATH"
# Keep the real environment from leaking into the subject under test.
unset CARGO_TARGET_DIR CACHE_TIER FFREIS_CACHE_TIER MUTANTS_TMPDIR

run_subject() { # run_subject <repo-dir> <rel-cwd> <threshold> -- env assignments...
  local dir="$1" rel="$2" thr="$3"; shift 3
  ( cd "$dir/$rel" && env MUTATION_BASE_REF=main "$@" bash "$subject" "$thr" 2>&1 )
}

# --- 1. no Rust changes -> PASS, and cargo is never invoked ------------------
d="$root/norust"; make_repo "$d" norust
rec="$root/rec1"; : > "$rec"
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp1" STUB_RECORD="$rec")"; rc=$?
if [[ $rc -eq 0 ]] && grep -q "nothing to mutate" <<<"$out" && [[ ! -s "$rec" ]]; then
  ok "diff with no .rs changes passes without invoking cargo"
else
  bad "diff with no .rs changes passes without invoking cargo" "rc=$rc" "$out"
fi

# --- 2. scratch dir inside the repo -> hard FAIL (recursive-copy trap) -------
d="$root/inside"; make_repo "$d" rust
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$d/scratch")"; rc=$?
if [[ $rc -eq 1 ]] && grep -q "INSIDE the repo" <<<"$out"; then
  ok "scratch dir inside the repo is rejected, not silently used"
else
  bad "scratch dir inside the repo is rejected, not silently used" "rc=$rc" "$out"
fi

# --- 3. cargo dies without writing mutants.out -> FAIL (harness failure) -----
d="$root/harness"; make_repo "$d" rust
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp3" STUB_RC=4)"; rc=$?
if [[ $rc -eq 1 ]] && grep -q "harness failure" <<<"$out"; then
  ok "non-zero exit with no mutants.out fails instead of passing vacuously"
else
  bad "non-zero exit with no mutants.out fails instead of passing vacuously" "rc=$rc" "$out"
fi

# --- 4. clean exit, nothing mutable -> PASS ---------------------------------
d="$root/nomutants"; make_repo "$d" rust
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp4" STUB_RC=0)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q "nothing mutable" <<<"$out"; then
  ok "clean exit with nothing mutable is a pass, distinct from a harness failure"
else
  bad "clean exit with nothing mutable is a pass, distinct from a harness failure" "rc=$rc" "$out"
fi

# --- 5. scoring: at threshold passes, below it fails -------------------------
d="$root/score"; make_repo "$d" rust
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp5a" STUB_RC=2 STUB_CAUGHT=7 STUB_MISSED=3)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q "Score: 70%" <<<"$out"; then
  ok "7 caught / 3 missed scores 70% and passes a 70% threshold"
else
  bad "7 caught / 3 missed scores 70% and passes a 70% threshold" "rc=$rc" "$out"
fi

rm -rf "$d/mutants.out"
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp5b" STUB_RC=2 STUB_CAUGHT=6 STUB_MISSED=4)"; rc=$?
if [[ $rc -eq 1 ]] && grep -q "below threshold" <<<"$out"; then
  ok "6 caught / 4 missed scores 60% and fails a 70% threshold"
else
  bad "6 caught / 4 missed scores 60% and fails a 70% threshold" "rc=$rc" "$out"
fi

# --- 6. the mutated environment cargo is handed ------------------------------
d="$root/env"; make_repo "$d" rust
rec="$root/rec6"; : > "$rec"
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp6" STUB_RC=0 STUB_CAUGHT=1 \
        STUB_RECORD="$rec" CARGO_TARGET_DIR="$root/poison")"; rc=$?
tmpdir_line="$(grep '^TMPDIR: ' "$rec" | head -1 | cut -d' ' -f2-)"
if grep -q '^CARGO_TARGET_DIR: <unset>' "$rec" && [[ "$tmpdir_line" == "$root/tmp6/"* ]]; then
  ok "inherited CARGO_TARGET_DIR is stripped and TMPDIR points into the scratch"
else
  bad "inherited CARGO_TARGET_DIR is stripped and TMPDIR points into the scratch" "$(cat "$rec")"
fi

# --- 7. the scratch dir does not survive the run -----------------------------
if [[ -d "$root/tmp6" ]] && [[ -z "$(ls -A "$root/tmp6")" ]]; then
  ok "scratch dir is removed on exit (no multi-GB leak per run)"
else
  bad "scratch dir is removed on exit (no multi-GB leak per run)" "$(ls -A "$root/tmp6" 2>&1)"
fi

# --- 8. subdir crate: diff paths are relative to the source dir --------------
d="$root/subdir"; make_repo "$d" subdir
rec="$root/rec8"; : > "$rec"
out="$(run_subject "$d" crate 70 MUTANTS_TMPDIR="$root/tmp8" STUB_RC=0 STUB_CAUGHT=1 STUB_RECORD="$rec")"; rc=$?
if grep -q '^+++ b/src/lib.rs' "$rec" && ! grep -q '^+++ b/crate/src/lib.rs' "$rec"; then
  ok "crate in a subdirectory gets a diff relative to it, not to the repo root"
else
  bad "crate in a subdirectory gets a diff relative to it, not to the repo root" "$(cat "$rec")"
fi

# --- 9. --jobs: explicit value honoured, caller's own -j never doubled -------
d="$root/jobs"; make_repo "$d" rust
rec="$root/rec9"; : > "$rec"
out="$(run_subject "$d" . 70 MUTANTS_TMPDIR="$root/tmp9" STUB_RC=0 STUB_CAUGHT=1 \
        STUB_RECORD="$rec" MUTATION_JOBS=3)"
if grep -qE '^ARGS: .*--jobs 3' "$rec"; then
  ok "MUTATION_JOBS is passed through as --jobs"
else
  bad "MUTATION_JOBS is passed through as --jobs" "$(grep '^ARGS: ' "$rec")"
fi

rec="$root/rec10"; : > "$rec"
out="$( cd "$d" && env MUTATION_BASE_REF=main MUTANTS_TMPDIR="$root/tmp10" STUB_RC=0 \
        STUB_CAUGHT=1 STUB_RECORD="$rec" MUTATION_JOBS=3 \
        bash "$subject" 70 --jobs 1 2>&1 )"
# grep -c counts LINES, and the whole arg list is one line — count OCCURRENCES.
n_jobs="$(grep '^ARGS: ' "$rec" | grep -o -- '--jobs' | wc -l)"
if [[ "$n_jobs" -eq 1 ]] && grep -qE '^ARGS: .*--jobs 1' "$rec"; then
  ok "a caller-supplied --jobs wins and is not duplicated"
else
  bad "a caller-supplied --jobs wins and is not duplicated" "$(grep '^ARGS: ' "$rec")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
