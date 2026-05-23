# ffreis-platform-standards

Shared configuration standards for all repos in the ffreis fleet. Every repo extends from
here instead of copy-pasting configs.

## What lives here

| Directory | Purpose |
|---|---|
| `renovate/` | Renovate preset files. Repos extend via `"github>FelipeFuhr/ffreis-platform-standards:renovate/<preset>"` |
| `lefthook/` | Shared lefthook hooks. Repos pull via `remotes:` in their `lefthook.yml` |
| `golangci/` | Reference golangci-lint v2 config. Go repos copy `golangci/standard.yml` to `.golangci.yml` |

## Renovate presets

| File | Use for |
|---|---|
| `renovate/default.json` | Base preset (schedule, limits, github-actions automerge). Extended by all other presets |
| `renovate/go.json` | Go repos: gomod + dockerfile + github-actions |
| `renovate/python.json` | Python/uv repos: uv + dockerfile + github-actions |
| `renovate/python-pip.json` | Python repos using pep621/pip_requirements (not uv) |
| `renovate/rust.json` | Rust repos: cargo + dockerfile + github-actions |
| `renovate/terraform.json` | Terraform repos: terraform + github-actions |
| `renovate/github-actions.json` | Repos with no package manager (workflow libraries, deployers) |

Per-repo `renovate.json`:
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>FelipeFuhr/ffreis-platform-standards:renovate/go"]
}
```

To override limits (e.g. ffreis-mlflow):
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>FelipeFuhr/ffreis-platform-standards:renovate/go"],
  "prConcurrentLimit": 3,
  "prHourlyLimit": 1
}
```

## Lefthook remotes

Per-repo `lefthook.yml` (Go example):
```yaml
remotes:
  - git_url: https://github.com/FelipeFuhr/ffreis-platform-standards
    ref: main
    configs:
      - lefthook/base.yml
      - lefthook/go.yml

# repo-specific pre-push only:
pre-push:
  parallel: false
  commands:
    test:
      run: make test
```

Available shared configs:
- `lefthook/base.yml` — hygiene (merge markers, large files, binary files) + secret-scan + agents-drift-hint + commit-msg (ALL repos)
- `lefthook/go.yml` — go-mod-drift + fmt-check + lint
- `lefthook/python.yml` — fmt-check (Python glob)
- `lefthook/rust.yml` — fmt-check (Rust glob)
- `lefthook/terraform.yml` — fmt-check + tflint lint (Terraform glob)
- `lefthook/actionlint.yml` — actionlint on GitHub Actions workflows (optional, add for repos with significant workflow files)

**All hook logic is inlined in the YAML** — repos do NOT need local `scripts/hooks/*.sh`
files. The `scripts/bootstrap_lefthook.sh` still needs to be per-repo (it runs before
lefthook is installed, so it can't be a remote). Existing `scripts/hooks/*.sh` files in
repos are dead code once this config is pulled and can be removed.

To pin to a stable version instead of always tracking main:
```yaml
remotes:
  - git_url: https://github.com/FelipeFuhr/ffreis-platform-standards
    ref: v1.0.0  # pin to a release tag; Renovate will track updates
```

## golangci standard

Copy `golangci/standard.yml` to `.golangci.yml` in each Go repo. The config is golangci-lint
v2 format. The only value that may need adjustment per repo is `goimports.local-prefixes`
(default is `github.com/ffreis`, which covers all repos in this org).

## CI and versioning

**CI (`ci.yml`)** validates on every PR:
- `renovate/*.json` — valid JSON (python3 json.tool)
- `lefthook/*.yml` + `golangci/*.yml` — valid YAML
- Shell scripts — shellcheck
- Workflow files — actionlint + CodeQL

**Versioning (release-please)**: When `vars.RELEASE_PLEASE_ENABLED = 'true'` is set in
GitHub repo settings, merging conventional-commit PRs automatically creates versioned
releases (`v1.0.0`, `v1.1.0`, …). This lets fleet repos pin to stable preset versions:
```json
{"extends": ["github>FelipeFuhr/ffreis-platform-standards:renovate/go#v1.0.0"]}
```
Callers using `@main` always get the latest; callers pinning to a tag get stability.

**Renovate on this repo**: Managed via the top-level `renovate.json`, which tracks
`.github/workflows/` action SHA pins using the `github-actions` manager.

**Lefthook on this repo**: Self-referential — this repo uses its own `lefthook/base.yml`
and `lefthook/actionlint.yml` as the remote source.

## Local CI runner (`scripts/`)

Tooling for running GitHub Actions workflows locally via
[`act`](https://github.com/nektos/act). Intended as a fallback when GitHub
Actions monthly minutes are exhausted, **not** as a routine pre-commit
check (`make ci` is the routine check — see workspace `AGENTS.md`).

Two scripts, used together:

| Script | Purpose |
|---|---|
| `scripts/install_act.sh` | Downloads a pinned `act` binary into `.bin/act`. Mirrors the `lefthook/bootstrap_lefthook.sh` pattern (centralized version, fleet-wide consistency). Default: `ACT_VERSION=0.2.88`. |
| `scripts/run-ci-local.sh` | Self-contained `act` wrapper. Pins runner image inline (no external `.actrc` needed) so it works the same whether invoked directly or curl-downloaded into a repo. Auto-detects local credentials. |

### Per-repo Makefile snippet (recommended for active repos)

Paste this into a repo's `Makefile` — pattern mirrors how the lefthook
bootstrap is already pulled in (`.github/Makefile`, `ml/ffreis-integration-hub/Makefile`):

```makefile
PLATFORM_STANDARDS_SHA := <commit-sha>     # main as of YYYY-MM-DD
PLATFORM_STANDARDS_RAW := https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards

install-act: ## Download pinned act binary into .bin/
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/install_act.sh" \
		-o scripts/install_act.sh && chmod +x scripts/install_act.sh
	@bash ./scripts/install_act.sh

ci-local: ## Run workflows locally via act (GH Actions quota fallback)
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/run-ci-local.sh" \
		-o scripts/run-ci-local.sh && chmod +x scripts/run-ci-local.sh
	@PATH="$(CURDIR)/.bin:$(PATH)" bash ./scripts/run-ci-local.sh $(ARGS)
```

Pin `PLATFORM_STANDARDS_SHA` to a commit (not `main`) so script behavior
doesn't drift under you. The trailing comment documents what the SHA
corresponds to — Renovate keeps the SHA updated; humans update the comment
on the same PR.

After adding: `make install-act` once (caches the binary in `.bin/`), then
`make ci-local` (or `make ci-local ARGS=--quick`) any time.

### Alternative: shell alias (for cross-repo, no Makefile changes)

If you don't want to modify per-repo Makefiles, alias the script directly:

```bash
alias ci-local='bash /media/ffreis/second/projects/platform/ffreis-platform-standards/scripts/run-ci-local.sh'
```

Then `cd repo/ && ci-local`. Trades discoverability (no `make help` entry)
for zero per-repo churn.

### Credential auto-detection

The script never requires a credential — it passes through whatever it
finds and labels missing-secret failures separately from real failures.

| Source | Detected via | Passed as |
|---|---|---|
| AWS (env) | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` exported | `--secret AWS_*` |
| AWS (profile) | `aws sts get-caller-identity` with `AWS_PROFILE` (default `ffreis-platform`) | resolved via `aws configure export-credentials` (requires AWS CLI v2.13+) |
| GitHub token | `gh auth token` succeeds | `--secret GITHUB_TOKEN` |
| Anything else (reCAPTCHA, Sonar, …) | `~/.config/ffreis/ci-local.env` (user-managed, never committed) | `--secret KEY=VALUE` per line |

Template at `scripts/ci-local.env.example`. Copy to
`~/.config/ffreis/ci-local.env` (NOT into any repo) and fill in only
secrets you actually have locally.

### Prerequisites

- `act` installed — preferably via `install_act.sh` for fleet-pinned version
  (override with `ACT_VERSION` env var). Alternative: system package manager.
- Docker daemon running.
- Runner image (`ghcr.io/catthehacker/ubuntu:act-22.04`, ~500MB) pulls on
  first run. Override with `ACT_RUNNER_IMAGE` env var.

### Limits

- Won't replicate macOS matrix runners (`act` is Linux-only).
- Container builds run but GHCR push is blocked (no token).
- Anything depending on real GitHub API state (PR comments, scheduled
  triggers, environment approvals) won't execute meaningfully.

For deploy / promote / `tf-apply` workflows specifically: prefer waiting
for real CI to recover. The script does not block them, but a local
"success" doesn't mean the live deploy would succeed.

## Making fleet-wide changes

1. Update the relevant file in this repo
2. Open a PR — CI validates JSON/YAML/shell automatically
3. Merge to main
4. Renovate runs pick up changes fleet-wide; lefthook `remotes:` pulls on next `lefthook install`

---

## Workspace Essentials

Quick reference for agents and new contributors. Detailed docs live in
`FelipeFuhr/ffreis-website-inventory` → `AGENTS.md`.

### Branching model

| Repo type | Branches | Deploy trigger |
|-----------|----------|----------------|
| Website/KB content repos | `develop` + `main` | push to `develop` → dev; push to `main` → prod |
| Tools, infra, libraries | `main` only | push to `main` (or manual) |

Always create a feature branch off `develop` (content repos) or `main` (tool repos).
Open a PR. **Never push directly to `main` or `develop`.**

### Secrets checklist for new repos

| Secret | Purpose | Where |
|--------|---------|--------|
| `CODECOV_TOKEN` | Code coverage upload | GitHub repo secrets |
| `RELEASE_PLEASE_TOKEN` | Release automation PAT | GitHub repo secrets |
| `CI_REPO_READ_TOKEN` | Check out private inventory / sibling repos | GitHub repo secrets |
| `CI_DISPATCH_TOKEN` | Dispatch to `ffreis-website-deployer` (write scope) | GitHub repo secrets (source repos only) |
| `AWS_DEPLOY_ROLE_ARN` | OIDC deploy role ARN | GitHub environment secrets (`prod`, `*-dev`) |
| `CF_DISTRIBUTION_ID` | CloudFront distribution ID | GitHub environment secrets |
| `S3_WEBSITE_BUCKET` | Live S3 bucket name | GitHub environment secrets |

### GitHub variables checklist

| Variable | Value | Where |
|----------|-------|--------|
| `SCORECARD_ENABLED` | `'true'` or `'false'` | Repo variables |
| `RELEASE_PLEASE_ENABLED` | `'true'` or `'false'` | Repo variables |
| `STALE_ENABLED` | `'true'` or `'false'` | Repo variables |
| `BUILDS_BUCKET` | S3 builds bucket name | Environment variables (`prod`, `*-dev`) |

### Local dev

```bash
make setup          # after cloning any repo; installs tooling + hooks
```

For website builds locally, use `ffreis-siteops` (NOT the deployer — that's CI only):
```bash
cd ffreis-siteops
make build SITE=flemming ENV=dev
```

### Agent safety rules

These rules are also in the workspace `CLAUDE.md` and apply to every session:
- NEVER push directly to `main` or `develop` — always use a PR
- NEVER run `terraform apply ENV=prod` without explicit user confirmation
- When in doubt about dev vs prod, choose dev and ask
