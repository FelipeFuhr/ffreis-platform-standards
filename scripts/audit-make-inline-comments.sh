#!/usr/bin/env bash
# audit-make-inline-comments.sh — find (and repair) make variable assignments
# whose trailing inline `# comment` leaves whitespace INSIDE the value.
#
# The defect: GNU make strips the comment but NOT the whitespace that preceded
# the `#`. So
#
#     PLATFORM_STANDARDS_SHA := 3c787edb...8db7  # v1.2.1
#
# assigns a 42-character value — the 40-hex SHA plus two trailing spaces.
# `?=` does not help; the operator is irrelevant. Every recipe that interpolates
# the variable into a quoted URL then builds a malformed URL and dies with
#
#     curl: (3) URL rejected: Malformed input to a URL function
#
# Measured on petlook-website and ffreis-platform-cli 2026-10-19: len=42, which
# broke those repos' whole local-gate surface (hook-scripts, lefthook-bootstrap,
# lefthook-install, lefthook-run, lefthook, install-act, ci-local) — `make
# install-act` could never have worked there. The repair is to move the comment
# to its own line ABOVE the assignment; the value then measures 40 and the URL
# resolves.
#
# The defect is invisible in a diff and invisible to the eye, so this script
# both greps for the shape and (with --measure) proves the expanded length via
# a generated make probe rather than by inspection.
#
# Usage:
#   audit-make-inline-comments.sh                     # audit THIS repo
#   audit-make-inline-comments.sh <path> ...          # specific repos or files
#   audit-make-inline-comments.sh --workspace         # sweep the whole workspace
#   audit-make-inline-comments.sh --fix <path> ...    # repair in place (idempotent)
#   audit-make-inline-comments.sh --fatal-only        # only report URL/path interpolations
#   audit-make-inline-comments.sh --list-repos        # one repo path per violating repo
#   audit-make-inline-comments.sh --measure <repo>    # make-expanded byte length per variable
#   audit-make-inline-comments.sh --include-worktrees # also scan linked worktrees found BELOW a target
#
# Severity:
#   FATAL — the variable is interpolated adjacent to `/` (a URL or filesystem
#           path), so the embedded whitespace corrupts the resulting string.
#   WARN  — the trailing whitespace is real but currently lands only where the
#           shell or make re-splits on whitespace anyway (e.g. a `$(strip …)`-ed
#           use site, as in ffreis-articles).
#
# Exit: 0 = clean, 1 = violations found, 2 = setup error.
#
# Default scope is THIS REPO, not a machine-specific workspace path: this script
# runs in GitHub Actions (general-make-hygiene.yml) and in a lefthook hook as
# well as in a workspace sweep, and a default that happens to be one machine's
# path is how several seams in this fleet shipped broken. `--workspace` opts into
# the sweep and resolves the root from $FFREIS_WORKSPACE_ROOT (canonical) or
# $FFREIS_WORKSPACE (deprecated alias).
set -uo pipefail

FIX=0
FATAL_ONLY=0
LIST_REPOS=0
MEASURE=0
INCLUDE_WORKTREES=0
SWEEP=0
declare -a TARGETS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix) FIX=1 ;;
    --fatal-only) FATAL_ONLY=1 ;;
    --list-repos) LIST_REPOS=1 ;;
    --measure) MEASURE=1 ;;
    --include-worktrees) INCLUDE_WORKTREES=1 ;;
    --workspace) SWEEP=1 ;;
    -h | --help)
      sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "audit-make-inline-comments: unknown flag $1" >&2
      exit 2
      ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

if [ "$SWEEP" -eq 1 ]; then
  WS="${FFREIS_WORKSPACE_ROOT:-${FFREIS_WORKSPACE:-}}"
  [ -n "$WS" ] || {
    echo "audit-make-inline-comments: --workspace needs \$FFREIS_WORKSPACE_ROOT (or a path argument)" >&2
    exit 2
  }
  [ -d "$WS" ] || {
    echo "audit-make-inline-comments: workspace $WS not found" >&2
    exit 2
  }
  TARGETS+=("$WS")
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  # This repo. `git rev-parse` so an invocation from a subdirectory still
  # covers the whole repo (a hook may run from anywhere); plain `.` when the
  # cwd is not a git repo at all.
  self="$(git rev-parse --show-toplevel 2>/dev/null)" || self=""
  TARGETS=("${self:-.}")
fi

# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------
# Repo root for a path: nearest ancestor holding .git (dir = main checkout,
# file = linked worktree). Prints the path, or the starting dir if none.
repo_root_of_dir() {
  local d
  d="$(cd "$1" 2>/dev/null && pwd)" || return 0
  while [ "$d" != "/" ]; do
    if [ -e "$d/.git" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  printf '%s\n' "$1"
}

repo_root_of() { repo_root_of_dir "$(dirname "$1")"; }

# Enumerate make-syntax files under a path. Jinja/j2 variants are included
# because the Copier templates in ffreis-project-templates carry the same shape
# and are the upstream SOURCE of it — every scaffolded repo inherits it.
list_make_files() {
  local root="$1" target_root
  if [ -f "$root" ]; then
    printf '%s\n' "$root"
    return
  fi
  # The repo the caller actually pointed at. A linked worktree found BELOW this
  # is the same repo seen twice and is pruned; the target itself never is — a
  # session/Agent worktree is where this fleet does most of its work, and
  # pruning it made `audit-make-inline-comments.sh .` exit 0 there on a repo
  # whose origin/main measured 42 (verified on ffreis-platform-cli 2026-10-19).
  target_root="$(repo_root_of_dir "$root")"
  find "$root" -type f \
    \( -name Makefile -o -name makefile -o -name GNUmakefile \
    -o -name 'Makefile.jinja' -o -name 'Makefile.j2' \
    -o -name '*.mk' -o -name '*.mk.jinja' -o -name '*.mk.j2' \) \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/target/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -not -path '*/vendor/*' \
    -not -path '*/dist/*' \
    -not -path '*/.terraform/*' \
    -not -path '*/old/*' \
    -not -path '*/_orphaned/*' \
    2>/dev/null | {
    if [ "$INCLUDE_WORKTREES" -eq 1 ]; then
      cat
    else
      # Linked worktrees are the SAME repo seen twice, so fixing one there opens
      # a second branch for one defect. Path patterns alone cannot find them:
      # this workspace has session worktrees under <root>/.worktrees/, Agent-tool
      # worktrees under <repo>/.claude/worktrees/, ad-hoc wt-*/.wt-* siblings,
      # AND plain-named siblings (ml/ffreis-ml-crypto-rl-select) that look
      # exactly like independent repos. So test the TYPE: a linked worktree
      # records its gitdir in a .git FILE, a main checkout has a .git DIRECTORY.
      # The name filter stays only to drop full clones parked under .worktrees/,
      # which have a real .git directory and are structurally indistinguishable.
      grep -vE '(^|/)(\.worktrees|\.claude/worktrees|\.wt-[^/]*|wt-[^/]*)(/|$)' |
        while IFS= read -r f; do
          fr="$(repo_root_of "$f")"
          [ "$fr" = "$target_root" ] && {
            printf '%s\n' "$f"
            continue
          }
          [ -f "$fr/.git" ] && continue
          printf '%s\n' "$f"
        done
    fi
  } | sort -u
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
# Emits "<lineno>\t<var>\t<comment>" for every assignment whose value ends in
# whitespace because of an inline comment. Quote- and escape-aware: a `#`
# inside '...' or "..." or preceded by a backslash is not a comment.
#
# shellcheck disable=SC2016  # the awk program is intentionally single-quoted
detect_awk='
function is_ws(c) { return (c == " " || c == "\t") }
{
  line = $0
  if (substr(line, 1, 1) == "\t") next            # recipe line, not an assignment
  if (line ~ /^[ ]*#/) next                       # whole-line comment
  if (!match(line, /^[ ]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_.-]*[ \t]*(:::?=|:=|\?=|\+=|!=|=)/)) next
  op_end = RSTART + RLENGTH - 1
  var = line
  sub(/^[ ]*(export[ \t]+)?/, "", var)
  sub(/[ \t]*(:::?=|:=|\?=|\+=|!=|=).*$/, "", var)
  rhs = substr(line, op_end + 1)
  # locate the first unquoted, unescaped "#"
  q = ""; hash = 0
  for (i = 1; i <= length(rhs); i++) {
    c = substr(rhs, i, 1)
    if (c == "\\") { i++; continue }
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\"" || c == "'"'"'") { q = c; continue }
    if (c == "#") { hash = i; break }
  }
  if (hash == 0) next
  pre = substr(rhs, 1, hash - 1)
  if (pre !~ /[^ \t]/) next                       # value is empty anyway
  if (pre ~ /\\$/) next                           # line continuation, ambiguous
  last = substr(pre, length(pre), 1)
  if (!is_ws(last)) next                          # comment flush against value
  comment = substr(rhs, hash)
  sub(/[ \t]+$/, "", comment)
  printf "%d\t%s\t%s\n", FNR, var, comment
}'

# FATAL iff the variable is interpolated adjacent to a "/" — i.e. it lands in a
# URL or filesystem path, where embedded whitespace corrupts the string.
severity_of() {
  local file="$1" var="$2"
  if grep -qE "(/[\$]\(${var}\)|[\$]\(${var}\)/|/[\$]\{${var}\}|[\$]\{${var}\}/)" "$file"; then
    printf 'FATAL\n'
  else
    printf 'WARN\n'
  fi
}

# ---------------------------------------------------------------------------
# Repair: move the comment to its own line above the assignment.
# ---------------------------------------------------------------------------
fix_file() {
  local file="$1"
  shift
  local -a lines=("$@") # descending line numbers
  local tmp ln
  tmp="$(mktemp "${TMPDIR:-/tmp}/shasweep-fix.XXXXXX")" || return 1
  cp -- "$file" "$tmp" || return 1
  for ln in "${lines[@]}"; do
    # Split line $ln into "<indent><comment>" + "<assignment, right-trimmed>".
    awk -v target="$ln" '
      FNR == target {
        line = $0
        q = ""; hash = 0
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "\\") { i++; continue }
          if (q != "") { if (c == q) q = ""; continue }
          if (c == "\"" || c == "'"'"'") { q = c; continue }
          if (c == "#") { hash = i; break }
        }
        if (hash == 0) { print line; next }
        indent = line; sub(/[^ ].*$/, "", indent)
        comment = substr(line, hash); sub(/[ \t]+$/, "", comment)
        assign  = substr(line, 1, hash - 1); sub(/[ \t]+$/, "", assign)
        print indent comment
        print assign
        next
      }
      { print }
    ' "$tmp" >"$tmp.new" && mv -- "$tmp.new" "$tmp" || return 1
  done
  if cmp -s -- "$file" "$tmp"; then
    rm -f -- "$tmp" "$tmp.new"
    return 2 # nothing changed (already repaired) — idempotent no-op
  fi
  cat -- "$tmp" >"$file" || return 1
  rm -f -- "$tmp" "$tmp.new"
  return 0
}

# ---------------------------------------------------------------------------
# Measurement: prove the expanded value's byte length via a generated probe.
# ---------------------------------------------------------------------------
measure_vars() {
  local file="$1"
  shift
  local -a vars=("$@")
  local dir base probe v
  dir="$(dirname "$file")"
  base="$(basename "$file")"
  case "$base" in
    Makefile | makefile | GNUmakefile) ;;
    *)
      echo "    (measure: $base is not a top-level makefile — skipped)"
      return 0
      ;;
  esac
  probe="$(mktemp "${TMPDIR:-/tmp}/shasweep-probe.XXXXXX.mk")" || return 1
  {
    printf 'audit-make-inline-comments-probe:\n'
    for v in "${vars[@]}"; do
      # shellcheck disable=SC2016  # $(VAR)/$$(...) must reach make and the recipe shell, not bash
      printf '\t@printf "    %s len=%%s value=[%%s]\\n" "$$(printf %%s '"'"'$(%s)'"'"' | wc -c)" '"'"'$(%s)'"'"'\n' \
        "$v" "$v" "$v"
    done
  } >"$probe"
  (
    cd "$dir" 2>/dev/null || exit 1
    # MAKEFLAGS/MAKELEVEL are cleared and --no-print-directory passed because a
    # nested make otherwise prints "make[1]: Entering directory ..." onto stdout
    # and inherits the parent's -j/-s, both of which corrupt the measurement.
    env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS \
      make --no-print-directory -f "$base" -f "$probe" audit-make-inline-comments-probe 2>&1 |
      grep -E 'len=' || echo "    (measure: make could not expand — see repo's own gate)"
  )
  rm -f -- "$probe"
}

# ---------------------------------------------------------------------------
# Main sweep
# ---------------------------------------------------------------------------
violations=0
fatal=0
declare -a VIOL_REPOS=()

for target in "${TARGETS[@]}"; do
  [ -e "$target" ] || {
    echo "audit-make-inline-comments: no such path: $target" >&2
    continue
  }
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    hits="$(awk "$detect_awk" "$file" 2>/dev/null)"
    [ -n "$hits" ] || continue

    declare -a keep_lines=() keep_vars=()
    report=""
    while IFS=$'\t' read -r ln var comment; do
      [ -n "$ln" ] || continue
      sev="$(severity_of "$file" "$var")"
      [ "$FATAL_ONLY" -eq 1 ] && [ "$sev" != "FATAL" ] && continue
      keep_lines+=("$ln")
      keep_vars+=("$var")
      report+="  $sev $file:$ln  $var   trailing-ws-from  $comment"$'\n'
      violations=$((violations + 1))
      [ "$sev" = "FATAL" ] && fatal=$((fatal + 1))
    done <<<"$hits"

    [ "${#keep_lines[@]}" -gt 0 ] || continue
    VIOL_REPOS+=("$(repo_root_of "$file")")

    if [ "$LIST_REPOS" -eq 1 ]; then
      continue
    fi

    printf '%s' "$report"

    if [ "$MEASURE" -eq 1 ]; then
      mapfile -t uniq_vars < <(printf '%s\n' "${keep_vars[@]}" | sort -u)
      measure_vars "$file" "${uniq_vars[@]}"
    fi

    if [ "$FIX" -eq 1 ]; then
      mapfile -t desc < <(printf '%s\n' "${keep_lines[@]}" | sort -rn)
      if fix_file "$file" "${desc[@]}"; then
        echo "  FIXED $file (${#desc[@]} assignment(s))"
      else
        rc=$?
        if [ "$rc" -eq 2 ]; then
          echo "  NOOP  $file (already repaired)"
        else
          echo "  ERROR could not repair $file" >&2
          exit 2
        fi
      fi
      if [ "$MEASURE" -eq 1 ]; then
        mapfile -t uniq_vars < <(printf '%s\n' "${keep_vars[@]}" | sort -u)
        echo "  after fix:"
        measure_vars "$file" "${uniq_vars[@]}"
      fi
    fi
  done < <(list_make_files "$target")
done

if [ "$LIST_REPOS" -eq 1 ]; then
  [ "${#VIOL_REPOS[@]}" -gt 0 ] && printf '%s\n' "${VIOL_REPOS[@]}" | sort -u
  exit 0
fi

echo
echo "audit-make-inline-comments: $violations assignment(s) with comment-induced trailing whitespace ($fatal FATAL)"
[ "$violations" -eq 0 ] && exit 0
[ "$FIX" -eq 1 ] && exit 0
exit 1
