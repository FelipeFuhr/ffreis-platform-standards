#!/usr/bin/env bash
# check-repo-parity.sh — Audit a workspace repo against its Copier template.
#
# Why: when a new repo is bootstrapped without Copier (or scaffolded long
# before the template grew a file), it drifts behind the template. Missed
# files = missed platform maturity (CI, lefthook, renovate, release-please,
# etc.). This script enumerates the expected file set from the template
# and reports which paths are missing in the target repo.
#
# Usage:
#   bash quality-kit/scripts/check-repo-parity.sh <repo-dir>
#   bash quality-kit/scripts/check-repo-parity.sh \
#     --template terraform-infra <repo-dir>         # override autodetect
#   bash quality-kit/scripts/check-repo-parity.sh --verbose <repo-dir>
#
# Auto-detects the template from <repo-dir>/.copier-answers.yaml (specifically
# the `_src_path` line). If the file is missing, exits 4 with the suggested
# `copier copy …` command to either scaffold cleanly or backfill the answers.
#
# Output (one path per line; exit code reflects MISSING count):
#   MISSING: <path>      file present in template, absent in repo
#   EXTRA:   <path>      file present in repo, absent in template (with --verbose)
#
# Exit codes:
#   0 — repo is at parity with the template (no missing files)
#   2 — at least one MISSING file
#   3 — bad invocation (no repo path, repo path missing, etc.)
#   4 — no .copier-answers.yaml in the repo and --template not specified

set -euo pipefail

PROGNAME=$(basename "$0")
WORKSPACE_ROOT=${WORKSPACE_ROOT:-/media/ffreis/second/projects}
TEMPLATES_DIR=${TEMPLATES_DIR:-$WORKSPACE_ROOT/platform/ffreis-project-templates/templates}
VERBOSE=0
TEMPLATE_OVERRIDE=""

usage() {
    cat <<EOF
Usage: $PROGNAME [--template <name>] [--verbose] <repo-dir>

Audit <repo-dir> against the Copier template recorded in its
.copier-answers.yaml (or the explicitly-specified --template).

Options:
  --template <name>   Override autodetection. <name> is a subdirectory
                      of $TEMPLATES_DIR (e.g. terraform-infra, go-cli).
  --verbose           Also print EXTRA: paths (files in the repo not in
                      the template). These are usually fine — repos
                      legitimately diverge — but useful in audits.
  -h, --help          Show this help.

Environment:
  WORKSPACE_ROOT      Defaults to /media/ffreis/second/projects.
  TEMPLATES_DIR       Defaults to \$WORKSPACE_ROOT/platform/
                      ffreis-project-templates/templates.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --template)
            TEMPLATE_OVERRIDE="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "$PROGNAME: unknown flag: $1" >&2
            usage >&2
            exit 3
            ;;
        *)
            if [[ -z "${REPO_DIR:-}" ]]; then
                REPO_DIR="$1"
            else
                echo "$PROGNAME: unexpected extra argument: $1" >&2
                usage >&2
                exit 3
            fi
            shift
            ;;
    esac
done

if [[ -z "${REPO_DIR:-}" ]]; then
    echo "$PROGNAME: missing <repo-dir>" >&2
    usage >&2
    exit 3
fi

if [[ ! -d "$REPO_DIR" ]]; then
    echo "$PROGNAME: not a directory: $REPO_DIR" >&2
    exit 3
fi

# ── Resolve template ─────────────────────────────────────────────────────────

ANSWERS_FILE="$REPO_DIR/.copier-answers.yaml"
TEMPLATE_NAME=""

if [[ -n "$TEMPLATE_OVERRIDE" ]]; then
    TEMPLATE_NAME="$TEMPLATE_OVERRIDE"
elif [[ -f "$ANSWERS_FILE" ]]; then
    # Parse the _src_path line. Expected format:
    #   _src_path: gh:FelipeFuhr/ffreis-project-templates --subdirectory templates/<name>
    # or a workspace-local path. We just grep for the templates/<name> suffix.
    src_line=$(grep -E '^_src_path:' "$ANSWERS_FILE" | head -1 || true)
    if [[ -n "$src_line" ]]; then
        TEMPLATE_NAME=$(echo "$src_line" | sed -nE 's|.*templates/([a-zA-Z0-9_-]+).*|\1|p')
    fi
fi

if [[ -z "$TEMPLATE_NAME" ]]; then
    cat >&2 <<EOF
$PROGNAME: no template detected.

The repo at $REPO_DIR has no .copier-answers.yaml, or the file does not
record a _src_path matching templates/<name>. Either:

  1. Pass --template <name> explicitly to compare against a specific
     template:
       bash $0 --template terraform-infra $REPO_DIR

  2. Backfill .copier-answers.yaml so this script (and future
     \`copier update\`) can find the template automatically. Example:

       cat > $REPO_DIR/.copier-answers.yaml <<'YAML'
       _commit: HEAD
       _src_path: gh:FelipeFuhr/ffreis-project-templates --subdirectory templates/terraform-infra
       repo_name: <basename of the repo>
       github_org: FelipeFuhr
       # … other answers per templates/<name>/copier.yml
       YAML

  3. If this is a brand-new repo, scaffold it from the template instead
     of hand-rolling:
       copier copy gh:FelipeFuhr/ffreis-project-templates \\
         --subdirectory templates/<name> $REPO_DIR
EOF
    exit 4
fi

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME/template"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "$PROGNAME: template directory not found: $TEMPLATE_DIR" >&2
    echo "  Available templates: $(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)" >&2
    exit 3
fi

# Extract repo_name from .copier-answers.yaml (used to substitute the
# {{repo_name}} placeholder in template paths). Default to repo dir basename.
REPO_NAME=""
if [[ -f "$ANSWERS_FILE" ]]; then
    REPO_NAME=$(grep -E '^repo_name:' "$ANSWERS_FILE" | head -1 | sed -E 's/^repo_name:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)
fi
if [[ -z "$REPO_NAME" ]]; then
    REPO_NAME=$(basename "$(realpath "$REPO_DIR")")
fi

# ── Enumerate expected paths ────────────────────────────────────────────────
# Walk the template tree, normalize each path:
#   - strip the .jinja suffix (rendered to a real filename)
#   - substitute {{ repo_name }} / {{repo_name}} with the actual repo name
#   - emit one path per line, relative to the template root

normalize_path() {
    local p="$1"
    # Substitute {{repo_name}} variants (with or without whitespace).
    p=$(echo "$p" | sed -E 's|\{\{[[:space:]]*repo_name[[:space:]]*\}\}|'"$REPO_NAME"'|g')
    # Strip .jinja suffix.
    p="${p%.jinja}"
    echo "$p"
}

EXPECTED_LIST=$(mktemp)
ACTUAL_LIST=$(mktemp)
trap 'rm -f "$EXPECTED_LIST" "$ACTUAL_LIST"' EXIT

# Expected files: every file under the template, with placeholders resolved.
(cd "$TEMPLATE_DIR" && find . -type f) | sed 's|^\./||' | while IFS= read -r path; do
    normalize_path "$path"
done | sort -u >"$EXPECTED_LIST"

# Actual files: every tracked file in the repo (limit to what git knows about
# if it's a git repo; otherwise fall back to a plain find).
if [[ -d "$REPO_DIR/.git" ]] || (cd "$REPO_DIR" && git rev-parse --git-dir >/dev/null 2>&1); then
    (cd "$REPO_DIR" && git ls-files) | sort -u >"$ACTUAL_LIST"
else
    (cd "$REPO_DIR" && find . -type f -not -path './.git/*') | sed 's|^\./||' | sort -u >"$ACTUAL_LIST"
fi

# ── Report drift ────────────────────────────────────────────────────────────

MISSING=$(comm -23 "$EXPECTED_LIST" "$ACTUAL_LIST" || true)
EXTRA=$(comm -13 "$EXPECTED_LIST" "$ACTUAL_LIST" || true)

missing_count=0
if [[ -n "$MISSING" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "MISSING: $line"
        missing_count=$((missing_count + 1))
    done <<< "$MISSING"
fi

if [[ "$VERBOSE" = "1" && -n "$EXTRA" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "EXTRA:   $line"
    done <<< "$EXTRA"
fi

if [[ "$missing_count" -eq 0 ]]; then
    echo "ok: $REPO_DIR at parity with templates/$TEMPLATE_NAME"
    exit 0
fi

echo "" >&2
echo "$missing_count file(s) missing vs templates/$TEMPLATE_NAME. To fix, either:" >&2
echo "  1. Run \`copier update $REPO_DIR\` (requires .copier-answers.yaml)" >&2
echo "  2. Manually add the missing files using $TEMPLATE_DIR as reference" >&2
exit 2
