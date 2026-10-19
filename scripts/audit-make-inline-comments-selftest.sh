#!/usr/bin/env bash
# audit-make-inline-comments-selftest.sh — behaviour lock for
# scripts/audit-make-inline-comments.sh.
#
# Hermetic: builds its own throwaway trees under $TMPDIR, shells out to `make`
# only to MEASURE an expanded value (the defect is whitespace, so a byte length
# is the only honest assertion — the source line looks identical either way),
# and makes zero network calls.
#
# A gate whose test cannot fail is not a gate, so this file asserts BOTH
# directions for every rule: the defective shape must exit 1, and each
# legitimate shape that merely LOOKS like it must exit 0.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audit-make-inline-comments.sh"
[ -x "$SCRIPT" ] || {
  echo "selftest: $SCRIPT is not executable" >&2
  exit 2
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/make-comments-selftest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
CASES=0

# Keep a workspace sweep from reaching the real machine during the test run.
unset FFREIS_WORKSPACE_ROOT FFREIS_WORKSPACE GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true

ok() {
  CASES=$((CASES + 1))
  printf '  ok   %s\n' "$1"
}

bad() {
  CASES=$((CASES + 1))
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '       %s\n' "$2" >&2
  return 0
}

# run <expected-exit> <label> -- <args...>
run_case() {
  local want="$1" label="$2"
  shift 3
  local out status
  # `out=$(...)` under `set -e` would abort the whole run on the very exit code
  # this function exists to assert, so capture the status explicitly.
  out="$("$SCRIPT" "$@" 2>&1)" && status=0 || status=$?
  if [ "$status" -eq "$want" ]; then
    ok "$label"
  else
    bad "$label" "expected exit $want, got $status: $(printf '%s' "$out" | tr '\n' '|')"
  fi
  LAST_OUTPUT="$out"
}

# The summary line always ends in "(N FATAL)", so a substring match on "FATAL"
# is not a severity assertion — it passes on a clean report. Read the per-finding
# lines, which start with two spaces and the severity token.
assert_warn_not_fatal() {
  local label="$1"
  if printf '%s\n' "$LAST_OUTPUT" | grep -qE '^  FATAL '; then
    bad "$label" "a FATAL finding was reported"
  elif printf '%s\n' "$LAST_OUTPUT" | grep -qE '^  WARN '; then
    ok "$label"
  else
    bad "$label" "no WARN finding reported: $LAST_OUTPUT"
  fi
}

# assert_ok_if <command...> -- <label>: pass when the command succeeds.
# Written as an if/else rather than `cmd && ok || bad` because `A && B || C`
# also runs C when B fails, which would double-count a case (SC2015).
assert_ok_if() {
  local -a cmd=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    cmd+=("$1")
    shift
  done
  shift || true
  if "${cmd[@]}"; then
    ok "$1"
  else
    bad "$1"
  fi
}

# assert_len <makefile> <var> <expected> <label> — the defect is whitespace, so
# the make-expanded byte length is the only honest assertion.
assert_len() {
  local got
  got="$(measured_len "$1" "$2")"
  if [ "$got" = "$3" ]; then
    ok "$4"
  else
    bad "$4" "got $got"
  fi
}

# measured_len <makefile> <var> — the make-expanded byte length of $var.
measured_len() {
  local mk="$1" var="$2" probe
  probe="$TMP/probe.mk"
  {
    printf 'selftest-probe:\n'
    # shellcheck disable=SC2016  # $(VAR) must reach make, not bash
    printf '\t@printf %%s '"'"'$(%s)'"'"' | wc -c\n' "$var"
  } >"$probe"
  (
    cd "$(dirname "$mk")" || exit 1
    env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS \
      make --no-print-directory -f "$(basename "$mk")" -f "$probe" selftest-probe 2>/dev/null |
      tr -cd '0-9'
  )
}

seed() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

echo "audit-make-inline-comments selftest"

# -- 1. the real fleet shape: FATAL, and it measures 42 not 40 ---------------
MK="$TMP/fatal/Makefile"
seed "$MK" <<'EOF'
PLATFORM_STANDARDS_SHA := 3c787edb4e96ddea2e86b2add2c32139685e8db7  # v1.2.1
PLATFORM_STANDARDS_RAW := https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards

hook-scripts:
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/lefthook/bootstrap_lefthook.sh" -o /dev/null
EOF
run_case 1 "the fleet shape exits 1" -- "$MK"
case "$LAST_OUTPUT" in
  *FATAL*PLATFORM_STANDARDS_SHA*) ok "classified FATAL (interpolated next to '/')" ;;
  *) bad "classified FATAL" "$LAST_OUTPUT" ;;
esac
assert_len "$MK" PLATFORM_STANDARDS_SHA 42 "unfixed value measures 42"

# -- 2. --fix drives it to 40 and is idempotent ------------------------------
run_case 0 "--fix exits 0" -- --fix "$MK"
assert_len "$MK" PLATFORM_STANDARDS_SHA 40 "fixed value measures 40"
assert_ok_if grep -qx '# v1.2.1' "$MK" -- "comment preserved on its own line above"
assert_ok_if grep -qxE 'PLATFORM_STANDARDS_SHA := [0-9a-f]{40}' "$MK" -- "assignment right-trimmed"
before="$(cat "$MK")"
run_case 0 "a repaired file now exits 0" -- "$MK"
run_case 0 "--fix on a repaired file exits 0" -- --fix "$MK"
assert_ok_if [ "$before" = "$(cat "$MK")" ] -- "--fix is idempotent (byte-identical)"

# -- 3. ?= does not help: the operator is irrelevant -------------------------
MK="$TMP/operator/Makefile"
seed "$MK" <<'EOF'
SHA ?= 3c787edb4e96ddea2e86b2add2c32139685e8db7  # v1.2.1
URL := x/$(SHA)/y
EOF
assert_len "$MK" SHA 42 "?= still measures 42"
run_case 1 "?= is still a violation" -- "$MK"

# -- 4. the legitimate forms must NOT fail -----------------------------------
MK="$TMP/legit-flush/Makefile"
seed "$MK" <<'EOF'
SHA := abc# tag
URL := x/$(SHA)/y
EOF
run_case 0 "a comment flush against the value is clean" -- "$MK"

MK="$TMP/legit-quotes/Makefile"
seed "$MK" <<'EOF'
COLOR := "#fff"
OTHER := '#not-a-comment'
EMPTY =   # nothing
EOF
run_case 0 "a '#' inside quotes, and an empty value, are clean" -- "$MK"

MK="$TMP/legit-recipe/Makefile"
seed "$MK" <<'EOF'
all:
	@echo hi  # trailing note
EOF
run_case 0 "recipe lines are never read as assignments" -- "$MK"

MK="$TMP/legit-continuation/Makefile"
seed "$MK" <<'EOF'
HOOK_SCRIPTS := \
	check_binary_files.sh \
	check_large_files.sh
EOF
run_case 0 "line continuations are clean" -- "$MK"

MK="$TMP/legit-clean/Makefile"
seed "$MK" <<'EOF'
# v1.2.1
SHA := 3c787edb4e96ddea2e86b2add2c32139685e8db7
URL := x/$(SHA)/y
EOF
run_case 0 "the repaired shape is clean" -- "$MK"
case "$LAST_OUTPUT" in
  *"0 assignment(s)"*) ok "clean file reports zero" ;;
  *) bad "clean file reports zero" "$LAST_OUTPUT" ;;
esac

# -- 5. WARN vs FATAL, and --fatal-only --------------------------------------
# A non-path interpolation (and the $(strip …)-wrapped use site that makes
# ffreis-articles legitimately WARN-only) must not be reported as FATAL, and
# --fatal-only must drop it entirely.
MK="$TMP/warn/Makefile"
seed "$MK" <<'EOF'
ARCH ?= arm64   # arm64 or x86_64
build:
	@echo $(ARCH)
EOF
run_case 1 "a non-path interpolation is still reported" -- "$MK"
assert_warn_not_fatal "non-path interpolation is WARN, not FATAL"
run_case 0 "--fatal-only drops the WARN" -- --fatal-only "$MK"

MK="$TMP/strip/Makefile"
seed "$MK" <<'EOF'
REF ?= v1.2.0   # pinned release
URL := https://example.invalid/$(strip $(REF))/x
EOF
run_case 1 "a \$(strip …)-wrapped use site is still reported" -- "$MK"
assert_warn_not_fatal "\$(strip …) use site is WARN, not FATAL"

# -- 6. Copier templates (the upstream source of the defect) -----------------
MK="$TMP/template/Makefile.jinja"
seed "$MK" <<'EOF'
PLATFORM_STANDARDS_SHA := 3c787edb4e96ddea2e86b2add2c32139685e8db7  # v1.2.1
X := a/$(PLATFORM_STANDARDS_SHA)/b
EOF
run_case 1 "Makefile.jinja templates are scanned" -- "$MK"

# -- 7. repo enumeration and worktree handling -------------------------------
WS="$TMP/ws"
mkdir -p "$WS/repo/.git"
seed "$WS/repo/Makefile" <<'EOF'
SHA := abc  # tag
URL := x/$(SHA)/y
EOF
run_case 0 "--list-repos exits 0 even with violations" -- --list-repos "$WS"
assert_ok_if [ "$(printf '%s\n' "$LAST_OUTPUT" | grep -c .)" = "1" ] -- \
  "--list-repos prints the repo root once, not the file"

# A linked worktree BELOW the target is the same repo seen twice — pruned.
mkdir -p "$WS/repo/.claude/worktrees/agent-x" "$WS/.worktrees/sess/repo" "$WS/wt-adhoc" "$WS/.wt-adhoc"
for d in "repo/.claude/worktrees/agent-x" ".worktrees/sess/repo" "wt-adhoc" ".wt-adhoc"; do
  seed "$WS/$d/Makefile" <<'EOF'
SHA := abc  # tag
URL := x/$(SHA)/y
EOF
done
run_case 1 "a sweep reports only the real repo, not its worktrees" -- "$WS"
case "$LAST_OUTPUT" in
  *"1 assignment(s)"*) ok "nested worktrees pruned (1 of 5 reported)" ;;
  *) bad "nested worktrees pruned" "$LAST_OUTPUT" ;;
esac
run_case 1 "--include-worktrees reports all of them" -- --include-worktrees "$WS"
case "$LAST_OUTPUT" in
  *"5 assignment(s)"*) ok "--include-worktrees reports 5" ;;
  *) bad "--include-worktrees reports 5" "$LAST_OUTPUT" ;;
esac

# A plain-named linked worktree is pruned on its .git TYPE, not on its name:
# this workspace has siblings (ml/ffreis-ml-crypto-rl-select) that look exactly
# like independent repos.
mkdir -p "$WS/proj/.git" "$WS/proj-select"
seed "$WS/proj/Makefile" <<'EOF'
SHA := abc  # tag
URL := x/$(SHA)/y
EOF
seed "$WS/proj-select/Makefile" <<'EOF'
SHA := abc  # tag
URL := x/$(SHA)/y
EOF
printf 'gitdir: %s/proj/.git/worktrees/proj-select\n' "$WS" >"$WS/proj-select/.git"
run_case 1 "plain-named worktree pruned on .git type, not name" -- "$WS"
case "$LAST_OUTPUT" in
  *proj-select*) bad "proj-select must be pruned" "$LAST_OUTPUT" ;;
  *) ok "proj-select pruned while proj is reported" ;;
esac

# ...but the worktree the caller POINTED AT is never pruned. Pruning it made
# `audit-make-inline-comments.sh .` exit 0 inside every session/Agent worktree
# in this fleet — a vacuous pass on a repo measuring 42.
run_case 1 "an explicitly-targeted worktree IS scanned" -- "$WS/proj-select"
case "$LAST_OUTPUT" in
  *"1 assignment(s)"*) ok "targeted worktree reports its own violation" ;;
  *) bad "targeted worktree reports its own violation" "$LAST_OUTPUT" ;;
esac

# -- 8. default scope is this repo, never a hardcoded machine path -----------
if grep -q '/media/ffreis' "$SCRIPT"; then
  bad "no hardcoded workspace path in the script"
else
  ok "no hardcoded workspace path in the script"
fi
out="$(cd "$WS/proj" && "$SCRIPT" 2>&1)" && status=0 || status=$?
assert_ok_if [ "$status" -eq 1 ] -- "no-argument run audits the cwd's repo"
out="$("$SCRIPT" --workspace 2>&1)" && status=0 || status=$?
assert_ok_if [ "$status" -eq 2 ] -- "--workspace without a root fails loud (exit 2)"
out="$(FFREIS_WORKSPACE_ROOT="$WS" "$SCRIPT" --workspace --fatal-only 2>&1)" && status=0 || status=$?
assert_ok_if [ "$status" -eq 1 ] -- "--workspace honours \$FFREIS_WORKSPACE_ROOT"
printf '%s' "$out" >/dev/null

# -- 9. an unknown flag is a setup error, not a silent pass ------------------
run_case 2 "an unknown flag exits 2" -- --no-such-flag

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "audit-make-inline-comments selftest: $FAILURES of $CASES case(s) FAILED" >&2
  exit 1
fi
echo "audit-make-inline-comments selftest: all $CASES case(s) passed"
