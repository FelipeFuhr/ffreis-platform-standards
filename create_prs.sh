#!/usr/bin/env bash
# create_prs.sh — open PRs for all feat/platform-standards branches
#
# Prerequisites:
#   gh auth login          (run once before this script)
#   gh auth status         (verify you're logged in)
#
# Usage:
#   bash create_prs.sh                  # all repos
#   bash create_prs.sh ffreis-siteops   # single repo (partial name match)

set -euo pipefail

BRANCH=feat/platform-standards
FILTER="${1:-}"

BASE=/media/ffreis/second/projects

# repos that have the branch pushed — (local path relative to BASE) : (GitHub owner/repo)
declare -A REPOS=(
  [ffreis-siteops]="FelipeFuhr/ffreis-siteops"
  [ffreis-website-data]="FelipeFuhr/ffreis-website-data"
  [ffreis-website-deployer]="FelipeFuhr/ffreis-website-deployer"
  [ffreis-website-inventory]="FelipeFuhr/ffreis-website-inventory"
  [devops/ffreis-workflows-ai]="FelipeFuhr/ffreis-workflows-ai"
  [devops/ffreis-workflows-container]="FelipeFuhr/ffreis-workflows-container"
  [devops/ffreis-workflows-general]="FelipeFuhr/ffreis-workflows-general"
  [devops/ffreis-workflows-go]="FelipeFuhr/ffreis-workflows-go"
  [devops/ffreis-workflows-python]="FelipeFuhr/ffreis-workflows-python"
  [devops/ffreis-workflows-rust]="FelipeFuhr/ffreis-workflows-rust"
  [devops/ffreis-workflows-terraform]="FelipeFuhr/ffreis-workflows-terraform"
  [k8s-platform/ffreis-mlflow]="FelipeFuhr/ffreis-mlflow"
  [ml/ffreis-integration-hub]="FelipeFuhr/ffreis-integration-hub"
  [ml/ffreis-python-model-serving]="FelipeFuhr/ffreis-python-model-serving"
  [ml/ffreis-python-onnx-model-converter]="FelipeFuhr/ffreis-python-onnx-model-converter"
  [ml/ffreis-runner-comparison]="FelipeFuhr/ffreis-runner-comparison"
  [ml/ffreis-rust-onnx-model-serving]="FelipeFuhr/ffreis-rust-onnx-model-serving"
  [platform/ffreis-dynamoctl]="FelipeFuhr/ffreis-dynamoctl"
  [platform/ffreis-flemming-infra]="FelipeFuhr/ffreis-flemming-infra"
  [platform/ffreis-lambdas-packer]="FelipeFuhr/ffreis-lambdas-packer"
  [platform/ffreis-platform-bootstrap]="FelipeFuhr/ffreis-platform-bootstrap"
  [platform/ffreis-platform-cli]="FelipeFuhr/ffreis-platform-cli"
  [platform/ffreis-platform-configctl]="FelipeFuhr/ffreis-platform-configctl"
  [platform/ffreis-platform-github-oidc]="FelipeFuhr/ffreis-platform-github-oidc"
  [platform/ffreis-platform-guardian]="FelipeFuhr/ffreis-platform-guardian"
  [platform/ffreis-platform-orchestrator]="FelipeFuhr/ffreis-platform-orchestrator"
  [platform/ffreis-platform-org]="FelipeFuhr/ffreis-platform-org"
  [platform/ffreis-platform-project-template]="FelipeFuhr/ffreis-platform-project-template"
  [platform/ffreis-platform-runner]="FelipeFuhr/ffreis-platform-runner"
  [platform/ffreis-platform-terraform-modules]="FelipeFuhr/ffreis-platform-terraform-modules"
  [platform/ffreis-website-packer]="FelipeFuhr/ffreis-website-packer"
  [stock/ffreis-agents-runtime]="FelipeFuhr/ffreis-agents-runtime"
  [stock/ffreis-stock-simulator]="FelipeFuhr/ffreis-stock-simulator"
  [website/ffreis-website-compiler]="FelipeFuhr/ffreis-website-compiler"
  [website/ffreis-website-lambdas-rust]="FelipeFuhr/ffreis-website-lambdas-rust"
)

PR_BODY=$(cat <<'EOF'
## Summary

- `renovate.json` now extends `FelipeFuhr/ffreis-platform-standards` instead of an inline 34-line config
- `lefthook.yml` now pulls shared hooks via `remotes:` from `ffreis-platform-standards`
- `.golangci.yml` (where applicable) upgraded to v2 format using the fleet standard

Fleet-wide policy changes (schedule, automerge, limits, hook logic) are now controlled in one place: [ffreis-platform-standards](https://github.com/FelipeFuhr/ffreis-platform-standards).

## What changed per file type

**renovate.json** — 34-line inline config → 4-line preset extends. No behavior change except:
  - github-actions minor/patch updates now automerge (consistent with ffreis-workflows-* which already did this)
  - `config:base` (deprecated) replaced with `config:recommended` for workflow repos

**lefthook.yml** — hygiene + secret-scan + commit-msg hooks centralized in `lefthook/base.yml`; language-specific hooks (go-mod-drift, fmt-check, lint) in `lefthook/<lang>.yml`. Per-repo pre-push stays local.

**.golangci.yml** (Go repos only) — upgraded from v1 to v2 format; same linter set.

## Test plan

- [ ] Verify Renovate picks up the preset (check Renovate dashboard after merge)
- [ ] Confirm `lefthook install` runs without errors
- [ ] Confirm pre-commit hooks fire as expected on a test commit
EOF
)

OPENED=0
SKIPPED=0
FAILED=0

for rel in "${!REPOS[@]}"; do
  # Apply filter if given
  [[ -n "$FILTER" && "$rel" != *"$FILTER"* ]] && continue

  gh_repo="${REPOS[$rel]}"
  dir="$BASE/$rel"

  # Check remote branch exists
  if ! git -C "$dir" ls-remote --exit-code origin "$BRANCH" &>/dev/null 2>&1; then
    echo "SKIP (no remote branch): $rel"
    ((SKIPPED++)) || true
    continue
  fi

  # Check PR already exists
  existing=$(gh pr list --repo "$gh_repo" --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
  if [[ -n "$existing" ]]; then
    echo "SKIP (PR #$existing already exists): $rel"
    ((SKIPPED++)) || true
    continue
  fi

  echo -n "Opening PR: $rel ... "
  pr_url=$(gh pr create \
    --repo "$gh_repo" \
    --head "$BRANCH" \
    --base main \
    --title "feat(deps): migrate to ffreis-platform-standards" \
    --body "$PR_BODY" 2>&1)

  if echo "$pr_url" | grep -q "https://"; then
    echo "$pr_url"
    ((OPENED++)) || true
  else
    echo "FAILED: $pr_url"
    ((FAILED++)) || true
  fi
done

echo ""
echo "Opened: $OPENED  Skipped: $SKIPPED  Failed: $FAILED"
