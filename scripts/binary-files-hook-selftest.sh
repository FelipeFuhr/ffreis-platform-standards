#!/usr/bin/env bash
# Behaviour lock for lefthook/base.yml's `hygiene-binary-files` command.
#
# The hook body is EXTRACTED from base.yml and run against throwaway git
# repositories, rather than reimplemented here. A copy would drift and still
# pass, which is the failure this repo has already shipped twice: base.yml and
# check_commit_msg.sh disagreed about commit scopes for a long time because
# nothing asserted the two matched.
#
# What matters here is the asymmetry. The hook exists to catch an ACCIDENT --
# a stray build artifact, a pasted screenshot -- so it must keep rejecting
# anything undeclared. It must also let through a binary a repo genuinely
# means to carry, declared in .gitattributes, or a theme cannot ship the fonts
# its deck embeds and the only way past is --no-verify, which bypasses every
# other hook too.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base_yml="$repo_root/lefthook/base.yml"
[ -f "$base_yml" ] || { echo "FAIL: $base_yml not found" >&2; exit 1; }

hook_body=$(python3 - "$base_yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
try:
    body = doc["pre-commit"]["commands"]["hygiene-binary-files"]["run"]
except (KeyError, TypeError):
    sys.exit("could not find pre-commit.commands.hygiene-binary-files.run")
if "check-attr" not in body:
    sys.exit("extracted a hook body with no check-attr in it; the hook was restructured")
sys.stdout.write(body)
PY
) || { echo "FAIL: extracting the hook from base.yml. It was probably restructured — update this extractor." >&2; exit 1; }

hook_file=$(mktemp)
printf '%s\n' "$hook_body" > "$hook_file"
work=$(mktemp -d)
trap 'rm -rf "$work" "$hook_file"' EXIT

fails=0

# run_case <name> <expect:allow|reject> <gitattributes-or-empty> <file> ...
# Builds a fresh repo, stages the files, and runs the extracted hook in it.
run_case() {
  local name="$1" expect="$2" attrs="$3"; shift 3
  local dir
  dir="$work/$(printf '%s' "$name" | tr -cd 'a-z0-9-')"
  mkdir -p "$dir"
  git -C "$dir" init -q .
  [ -n "$attrs" ] && printf '%s\n' "$attrs" > "$dir/.gitattributes"

  local f
  for f in "$@"; do
    mkdir -p "$dir/$(dirname "$f")"
    case "$f" in
      # Four PNG header bytes are enough for file(1) to call it image/png.
      *.png) printf '\211PNG\r\n\032\n' > "$dir/$f" ;;
      # A TrueType offset table: this is what a vendored font looks like.
      *.ttf) printf '\000\001\000\000\000\000\000\000\000\000\000\000' > "$dir/$f" ;;
      *) printf 'plain text\n' > "$dir/$f" ;;
    esac
  done
  git -C "$dir" add -A >/dev/null 2>&1

  local got=allow
  ( cd "$dir" && bash "$hook_file" ) >/dev/null 2>&1 || got=reject

  if [ "$got" = "$expect" ]; then
    printf '  ok    %-48s %s\n' "$name" "$expect"
  else
    printf '  FAIL  %-48s want %s, got %s\n' "$name" "$expect" "$got"
    fails=$((fails + 1))
  fi
}

echo "hygiene-binary-files:"

# The check must keep doing its job.
run_case "undeclared png is rejected"            reject ""                      "shot.png"
run_case "undeclared font is rejected"           reject ""                      "theme/fonts/Roboto-Regular.ttf"
run_case "text needs no declaration"             allow  ""                      "README.md"
run_case "empty gitattributes changes nothing"   reject ""                      "shot.png"

# A declaration lets the thing a repo means to carry through.
run_case "font declared by extension"            allow  '*.ttf binary'          "theme/fonts/Roboto-Regular.ttf"
run_case "font declared by path"                 allow  'theme/fonts/** binary' "theme/fonts/Roboto-Bold.ttf"
run_case "several declared fonts"                allow  '*.ttf binary'          "a/X-Regular.ttf" "a/X-Bold.ttf" "a/X-Italic.ttf"
run_case "declared alongside undeclared text"    allow  '*.ttf binary'          "f.ttf" "notes.md"

# And only the declared thing: a declaration is not a blanket pass.
run_case "declaring ttf does not admit png"      reject '*.ttf binary'          "f.ttf" "shot.png"
run_case "declaring one path not another"        reject 'theme/** binary'       "theme/f.ttf" "other/shot.png"
run_case "a near-miss glob does not match"       reject '*.ttff binary'         "f.ttf"

# -text and -diff are NOT the binary macro and must not be read as it, or a
# repo normalising line endings would silently disable the check.
run_case "-text alone is not a declaration"      reject '*.ttf -text'           "f.ttf"
run_case "-diff alone is not a declaration"      reject '*.ttf -diff'           "f.ttf"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: $fails case(s)" >&2
  exit 1
fi
echo "all cases pass"
