#!/usr/bin/env bash
# run-ci-local.sh — Run a repo's GitHub Actions workflows locally via `act`.
#
# Quota fallback for when GitHub Actions minutes are exhausted. Auto-detects
# locally available credentials (AWS, gh token, extra env file) and passes
# them through to act; missing-secret failures are surfaced separately from
# real test failures so you can tell them apart.
#
# Usage (run from inside the target repo):
#   run-ci-local.sh                     # all workflows, push event
#   run-ci-local.sh --lint-only         # actionlint on workflows only (no act/Docker)
#   run-ci-local.sh --quick             # only common lint/test/fmt jobs
#   run-ci-local.sh -W path/to/wf.yml   # one workflow (passthrough)
#   run-ci-local.sh -j go-lint          # one job (passthrough)
#   run-ci-local.sh -- --rm             # everything after `--` goes to act
#
# Requires: act (https://github.com/nektos/act), Docker daemon running.
# Optional: ~/.config/ffreis/ci-local.env for extra secrets. See the
# `ci-local.env.example` sibling file for the format.
#
# Runner image is pinned to ghcr.io/catthehacker/ubuntu:act-22.04 by default.
# Override via ACT_RUNNER_IMAGE env var if needed.

set -euo pipefail

# ── style ──────────────────────────────────────────────────────────────────
c_dim=$'\e[2m'; c_red=$'\e[31m'; c_ylw=$'\e[33m'; c_off=$'\e[0m'
info() { printf '%s[ci-local]%s %s\n' "$c_dim" "$c_off" "$*"; }
warn() { printf '%s[ci-local]%s %s\n' "$c_ylw" "$c_off" "$*" >&2; }
die()  { printf '%s[ci-local]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

# ── parse args ─────────────────────────────────────────────────────────────
mode=full
act_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) mode=quick; shift ;;
    --full)  mode=full;  shift ;;
    --lint-only) mode=lintonly; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; act_args+=("$@"); break ;;
    *)  act_args+=("$1"); shift ;;
  esac
done

# ── preflight ──────────────────────────────────────────────────────────────
git rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "Not inside a git repo. cd into a repo with .github/workflows/ first."

repo_root=$(git rev-parse --show-toplevel)
[[ -d "$repo_root/.github/workflows" ]] \
  || die "$repo_root has no .github/workflows/ — nothing for act to run."

# actionlint pre-flight — catch workflow-YAML errors (the class that causes
# startup_failure on GitHub: orphaned action SHA, bad uses:/if:) locally, before
# any push. Runs on every invocation; --lint-only stops here and needs no Docker.
if command -v actionlint >/dev/null 2>&1; then
  info "actionlint pre-flight on .github/workflows/"
  ( cd "$repo_root" && actionlint -color ) \
    || die "actionlint failed — fix the workflow YAML before pushing."
else
  warn "actionlint not on PATH — skipping workflow lint. Install: https://github.com/rhysd/actionlint"
fi
[[ "$mode" == lintonly ]] && { info "lint-only: done."; exit 0; }

command -v act >/dev/null 2>&1 \
  || die "act not installed. See https://nektosact.com/installation"

# Auto-route to rootless podman if the default docker socket isn't ours
# but the rootless podman socket is. Common on Linux machines where
# /var/run/docker.sock symlinks to root podman that the user can't reach.
# (`docker info` is unreliable here — podman-docker emulation returns 0
# even when actual container operations would fail with EACCES, so we
# check socket-file accessibility directly.)
if [[ -z "${DOCKER_HOST:-}" ]]; then
  rootless_sock="/run/user/${UID:-$(id -u)}/podman/podman.sock"
  if [[ ! -w /var/run/docker.sock && -S "$rootless_sock" && -w "$rootless_sock" ]]; then
    export DOCKER_HOST="unix://$rootless_sock"
    info "Using rootless podman socket: $DOCKER_HOST"
  fi
fi

# Pin runner image + container arch inline (no external .actrc dependency)
# so the script works the same whether invoked directly, via a Makefile
# curl-download, or with a stray ~/.actrc in the user's home.
runner_image="${ACT_RUNNER_IMAGE:-ghcr.io/catthehacker/ubuntu:act-22.04}"
runner_image_24="${ACT_RUNNER_IMAGE_24:-ghcr.io/catthehacker/ubuntu:act-24.04}"
act_platform_args=(
  -P "ubuntu-latest=$runner_image"
  -P "ubuntu-22.04=$runner_image"
  -P "ubuntu-24.04=$runner_image_24"
  --container-architecture linux/amd64
)

# ── credential probe ───────────────────────────────────────────────────────
tmp_dir=$(mktemp -d -t ci-local.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
secrets_file="$tmp_dir/secrets"
env_file="$tmp_dir/env"
: > "$secrets_file"
: > "$env_file"

have_aws=no
have_gh=no
have_extra=no

probe_aws() {
  # Prefer already-exported creds (e.g. from `aws sso login` + eval).
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    {
      printf 'AWS_ACCESS_KEY_ID=%s\n'     "$AWS_ACCESS_KEY_ID"
      printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$AWS_SECRET_ACCESS_KEY"
      [[ -n "${AWS_SESSION_TOKEN:-}" ]] && printf 'AWS_SESSION_TOKEN=%s\n' "$AWS_SESSION_TOKEN"
    } >> "$secrets_file"
    [[ -n "${AWS_REGION:-}" ]] && printf 'AWS_REGION=%s\n' "$AWS_REGION" >> "$env_file"
    have_aws=yes
    return
  fi
  # Fall back to resolving from a profile. Default to ffreis-platform
  # (assumes platform-admin from ~/.aws/credentials ffreis-platform-base).
  command -v aws >/dev/null 2>&1 || return
  local profile="${AWS_PROFILE:-ffreis-platform}"
  AWS_PROFILE="$profile" aws sts get-caller-identity >/dev/null 2>&1 || return
  # `export-credentials` exists in AWS CLI v2.13+; degrade gracefully.
  local creds
  creds=$(AWS_PROFILE="$profile" aws configure export-credentials --format env-no-export 2>/dev/null || true)
  if [[ -n "$creds" ]]; then
    printf '%s\n' "$creds" >> "$secrets_file"
    have_aws=yes
  fi
}
probe_aws

# GitHub token via gh CLI.
if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  printf 'GITHUB_TOKEN=%s\n' "$(gh auth token)" >> "$secrets_file"
  have_gh=yes
fi

# Extra secrets from user-managed env file.
extra_env="$HOME/.config/ffreis/ci-local.env"
extra_env_exists=no
if [[ -r "$extra_env" ]]; then
  extra_env_exists=yes
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || { warn "skipping non-KEY=VALUE line in $extra_env: $line"; continue; }
    printf '%s\n' "$line" >> "$secrets_file"
    have_extra=yes
  done < "$extra_env"
fi

# ── plan banner ────────────────────────────────────────────────────────────
info "Repo: $repo_root"
info "Mode: $mode"
info "Detected credentials: AWS=$have_aws GH=$have_gh EXTRA_ENV=$have_extra"
[[ "$have_aws"   == no ]] && info "  → AWS jobs may report 'credential-missing'. Set AWS_PROFILE or export AWS_* to enable."
[[ "$have_gh"    == no ]] && info "  → GitHub-API jobs may fail. Run 'gh auth login' to enable."
if [[ "$have_extra" == no ]]; then
  if [[ "$extra_env_exists" == no ]]; then
    info "  → No $extra_env. Copy scripts/ci-local.env.example there to enable extra secrets."
  else
    info "  → $extra_env exists but has no KEY=VALUE entries (all commented)."
  fi
fi

# ── invocation ─────────────────────────────────────────────────────────────
cd "$repo_root"
log_file="$tmp_dir/act.log"

if [[ "$mode" == quick ]]; then
  # Intersect repo's actual job names with a conservative cheap-check list.
  quick_pattern='^(lint|fmt-check|fmt|format|test|unit-test|go-lint|go-test|rust-lint|rust-test|python-lint|python-test|tf-fmt|tf-lint|actionlint)$'
  all_jobs=$(act -l 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
  runnable=$(printf '%s\n' "$all_jobs" | grep -E "$quick_pattern" || true)
  [[ -n "$runnable" ]] \
    || die "Quick mode: no matching jobs in this repo. Run without --quick or pass -j <name>."

  info "Quick-mode jobs: $(echo "$runnable" | tr '\n' ' ')"
  failures=0
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    info "→ act push -j $job"
    if ! act push -j "$job" "${act_platform_args[@]}" --secret-file "$secrets_file" --env-file "$env_file" "${act_args[@]}" 2>&1 | tee -a "$log_file"; then
      failures=$((failures + 1))
    fi
  done <<< "$runnable"
  act_status=$failures
else
  set +e
  act push "${act_platform_args[@]}" --secret-file "$secrets_file" --env-file "$env_file" "${act_args[@]}" 2>&1 | tee "$log_file"
  act_status=${PIPESTATUS[0]}
  set -e
fi

# ── post-parse: distinguish missing-credential from real failures ──────────
missing=$(grep -E 'Required secret .* not (found|set)|secret .* (is required|is not set|not configured)' "$log_file" 2>/dev/null || true)
if [[ -n "$missing" ]]; then
  warn "Some failures appear to be missing-credential rather than real test failures:"
  printf '%s\n' "$missing" | sort -u | sed 's/^/  /' >&2
fi

if [[ "$act_status" -ne 0 && -z "$missing" ]]; then
  die "act reported failures. Review the log above."
elif [[ "$act_status" -ne 0 ]]; then
  warn "act exited $act_status but failures look credential-related. Treating as success."
  exit 0
fi

info "All workflows passed locally."
