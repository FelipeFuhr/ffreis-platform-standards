#!/usr/bin/env bash
# create_ci_tooling_prs.sh — open PRs for feat/ci-and-tooling branches
#
# Covers: ffreis-workflows-ai and ffreis-workflow-ai-standardizer
#
# Prerequisites: gh auth login

set -euo pipefail

BRANCH=feat/ci-and-tooling

AI_PR_BODY=$(cat <<'EOF'
## Summary

- `ci.yml`: add `workflows-policy` + `codeql-actions` jobs; fix invalid secret literal (LLM_API_KEY not required for dry-run)
- `ai-standardize.yml`: fix shell injection (inputs moved to env vars); fix dry_run boolean logic that caused `--dry-run` to always be appended; pin actions to SHA; make `LLM_API_KEY` optional (CLI validates at runtime when not dry-run)
- `devops-automation.yml`: align with fleet standard — SHA pins, scorecard/stale/release-please behind `vars.*` feature flags
- `devops-security.yml`: add trivy-fs, grype-fs, osv scanning; pin to SHA; remove `secrets: inherit` (banned by AGENTS.md)
- `devops-pr-hygiene.yml`: new — semantic-pr + actionlint validation on every PR
- `Makefile`: add help, fmt-check, lefthook-bootstrap/install, setup targets

## Test plan

- [ ] Open a draft PR to verify ci.yml self-test (dry-run) passes
- [ ] Verify actionlint runs clean on the workflow files
- [ ] Confirm devops-security.yml jobs appear on push to main after merge
EOF
)

STANDARDIZER_PR_BODY=$(cat <<'EOF'
## Summary

- `ci.yml` (new): Go CI via `ffreis-workflows-go` (fmt/lint/build/test) + `tasks-validate` job that builds the binary and runs `standardizer tasks validate`
- `devops-automation.yml` (new): stale/scorecard/release-please via ffreis-workflows-general
- `devops-pr-hygiene.yml` (new): semantic-pr + actionlint on every PR
- `devops-security.yml` (new): gitleaks + trivy-fs + grype-fs + osv (SHA-pinned)
- `run.yml`: fix shell injection (inputs.* → env vars); pin actions to SHA; type `dry_run` as boolean; add `retention-days` to artifact upload
- `renovate.json` (new): extends `ffreis-platform-standards:renovate/go`
- `.golangci.yml` (new): v2 format from fleet standard
- `Makefile`: add help, vet, security, fmt-check, lefthook targets
- `scripts/bootstrap_lefthook.sh` (new): download lefthook binary

## Test plan

- [ ] Verify CI (fmt/lint/build/test + tasks-validate) passes on this PR
- [ ] Confirm devops-pr-hygiene actionlint runs clean
- [ ] After merge, verify devops-security jobs run on main push
EOF
)

echo "Opening PR: ffreis-workflows-ai (feat/ci-and-tooling → feat/platform-standards)"
gh pr create \
  --repo FelipeFuhr/ffreis-workflows-ai \
  --head "$BRANCH" \
  --base feat/platform-standards \
  --title "feat(ci): add full CI/CD suite and fix shell injection" \
  --body "$AI_PR_BODY"

echo ""
echo "Opening PR: ffreis-workflow-ai-standardizer (feat/ci-and-tooling → main)"
gh pr create \
  --repo FelipeFuhr/ffreis-workflow-ai-standardizer \
  --head "$BRANCH" \
  --base main \
  --title "feat(ci): add full CI/CD suite, fix shell injection, add tooling" \
  --body "$STANDARDIZER_PR_BODY"
