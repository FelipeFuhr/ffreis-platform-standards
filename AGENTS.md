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

## Workspace docs (`workspace/`)

Agent-facing docs that live at the workspace root (above the individual
repos) — `AGENTS.md` (agent-agnostic) and `CLAUDE.md` (Claude-specific).
Tracked here so they're versioned and shareable rather than loose files
on a single machine.

| File | Purpose |
|---|---|
| `workspace/AGENTS.md` | Workspace-level guide for any AI assistant (Codex, Cursor, Claude, …). Mirrors agent-relevant rules from `CLAUDE.md` in agent-agnostic phrasing. |
| `workspace/CLAUDE.md` | Claude-specific workspace guide. Auto-loaded by Claude Code when invoked at workspace root. |

Both files reference relative paths under the workspace root (e.g.
`platform/ffreis-platform-standards/scripts/...`), so they're portable
across machines that follow the same layout.

### Install at workspace root

The expected pattern is to symlink them in so changes here propagate
without manual copy:

```bash
cd /path/to/workspace-root
ln -sf platform/ffreis-platform-standards/workspace/AGENTS.md AGENTS.md
ln -sf platform/ffreis-platform-standards/workspace/CLAUDE.md CLAUDE.md
```

(If you'd rather copy than symlink — e.g. so you can tweak per-machine —
just `cp` them. You'll fall behind on upstream edits then; treat the
copies as a snapshot.)

## Making fleet-wide changes

1. Update the relevant file in this repo
2. Open a PR — CI validates JSON/YAML/shell automatically
3. Merge to main
4. Renovate runs pick up changes fleet-wide; lefthook `remotes:` pulls on next `lefthook install`

## GitHub Actions CI standards

All `.github/workflows/*.yml` files in the fleet follow these rules. Apply to every
new workflow and every edit to an existing one.

### Required structural elements

| Element | Rule | Notes |
|---|---|---|
| `concurrency.cancel-in-progress: true` | Every push/PR workflow | Prevents stale runs racing with new commits |
| `timeout-minutes` per job | Every **direct** job | 15 min for quick checks, 30 min for builds/tests; never omit |
| `timeout-minutes` on `uses:` caller jobs | **Forbidden** (GitHub rejects) | Set the timeout inside the reusable workflow's job instead |
| `if: ${{ !github.event.pull_request.draft }}` | Every expensive job in PR-triggered workflows | Saves CI minutes on WIP branches |
| `permissions:` per job (least privilege) | Required, **no workflow-level `permissions:`** | See "Per-job permissions" below |
| Path filters on push/PR triggers | Required where applicable | Limit triggers to files that actually affect the workflow |

### Per-job permissions

GitHub's `permissions:` block grants scopes to the `GITHUB_TOKEN`. The default if omitted
varies by repo settings — never rely on the default.

Two rules:

1. **No top-level `permissions:` block.** Top-level grants apply to every job, which
   over-grants for jobs that don't need write access. Declare per job instead.
2. **Each job declares exactly what it needs**, read-only by default. Write scopes
   (e.g. `contents: write`, `pull-requests: write`) only on the specific job that
   performs the write.

Common patterns:

```yaml
jobs:
  test:
    timeout-minutes: 15
    permissions:
      contents: read           # checkout only
    runs-on: ubuntu-latest
    steps: ...

  codeql:
    timeout-minutes: 30
    permissions:
      contents: read
      security-events: write   # upload SARIF
      actions: read
    runs-on: ubuntu-latest
    steps: ...

  release:
    timeout-minutes: 15
    permissions:
      contents: write          # create tag/release
      pull-requests: write     # release-please PRs
    runs-on: ubuntu-latest
    steps: ...
```

For jobs that only call a reusable workflow (`uses:`):

```yaml
jobs:
  call-go-test:
    permissions:
      contents: read
    uses: FelipeFuhr/ffreis-workflows-go/.github/workflows/go-test.yml@v1
```

The caller's per-job permissions become the `GITHUB_TOKEN` scope inside the reusable
workflow. Reusable workflows in this fleet **also** declare per-job permissions
internally as defense-in-depth — callers should still pass the minimal set explicitly.

### Path filters

Workflows that only need to run when specific files change should declare path filters
on `push:` and `pull_request:`. This conserves the shared 71-repo CI minutes budget.

```yaml
on:
  push:
    branches: [main]
    paths:
      - '.github/workflows/**'
      - 'Makefile'
      - 'lefthook.yml'
  pull_request:
    paths:
      - '.github/workflows/**'
      - 'Makefile'
      - 'lefthook.yml'
```

Workflows that must always run (release, scheduled drift, scorecards, etc.) keep no
path filter. If a workflow has a `merge_group:` trigger, mirror the same paths there.

### Reusable workflows (devops/ffreis-workflows-*)

The same standards apply to reusable workflows defined in the `devops/` repos:

- Per-job `timeout-minutes` and `permissions:` are still required (defense-in-depth —
  callers shouldn't need to over-grant just because a reusable workflow under-declares).
- Reusable workflow definitions use `on: workflow_call:` so path filters don't apply,
  but the self-test/CI workflows that live alongside them do follow all the rules above.

---

## Workspace Essentials

Quick reference for agents and new contributors. Detailed docs live in
the fleet inventory repo → `AGENTS.md`.

### Branching model

| Repo type | Branches | Default PR base | Deploy trigger |
|-----------|----------|-----------------|----------------|
| Website/KB content repos | `develop` + `main` | `develop` | push to `develop` → dev; push to `main` → prod |
| Tools, infra, libraries | `main` only | `main` | push to `main` (or manual) |

**Repos with `develop`** follow a strict promote-then-sync flow:

```
main ──────────────────────────────────►  production
 ↑                                              ↑
 │  promote PR (develop → main)                 │
 │                                              │
develop ──────────────────────────────►  dev / staging
 ↑
 │  feature PRs (feature/* → develop)
feature/* (always branch off develop)
```

**Four invariants — no exceptions:**

1. **`main` only receives commits from `develop`** via a promote PR.
   Never merge a feature branch directly into `main`.
2. **`develop` always branches off `main`** — when `main` advances after a
   promote, `develop` must immediately be brought back in sync by merging
   `main` into `develop` via a `chore/sync-develop-from-main` PR.
3. **All feature/fix/chore branches start from `develop`**, never from `main`.
4. **`develop` is the default base branch** for all PRs in repos that have it.

**Syncing develop after a promote (after any main advance):**

```bash
# From the repo root — create a sync PR:
git fetch origin
git checkout -b chore/sync-develop-from-main origin/develop
git merge origin/main --no-ff -m "chore: sync develop from main"
git push -u origin HEAD
gh pr create --draft --base develop \
  --title "chore: sync develop from main" \
  --body "Routine sync — brings develop up to date after main advanced."
# Merge immediately; no review required.
```

Never push directly to `main` or `develop` — always use a PR, even for sync merges.

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
---

## Public repo hygiene policy

All repos under `FelipeFuhr/` that are **publicly visible** must never expose internal
architecture details beyond what external contributors need to contribute. This policy
was established after a 2026-05-29 audit found private repo names, internal domain
patterns, and an unredacted workspace `CLAUDE.md` committed to public repos.

### What IS acceptable in public repos

- References to other **public** repos (`ffreis-website-compiler`, `ffreis-siteops`,
  `ffreis-website-deployer`, `ffreis-platform-standards`, etc.)
- Public production domains (`ffreis.com`, `flemming.com.br`, `petlook.app`,
  `petlook.ai`)
- Generic descriptions: "the fleet inventory", "a private consumer", "internal infra",
  "private data repo", "the website Lambdas repo"
- Secret **names** (not values): `AWS_DEPLOY_ROLE_ARN`, `CF_DISTRIBUTION_ID`, etc.
- Operational patterns (branching model, CI rules, hook configs) that don't name private resources

### What is NOT acceptable in public repos

- **Private repo names**: any repo not listed on the public profile README
  (e.g., `ffreis-website`, `flemming-website`, `petlook-data`, `ffreis-website-inventory`,
  `ffreis-rust-shared`, `ffreis-tracker-sdk`, all `*-infra` repos)
- **Internal dev domains**: `*.ffreis.com` subdomains used for dev routing
  (e.g., `flemming.ffreis.com`, `dev.ffreis.com`)
- **Internal naming patterns**: AWS resource-naming conventions, S3 bucket patterns,
  API Gateway naming conventions (e.g., `-api-dev`)
- **Workspace context files**: `workspace/CLAUDE.md`, `workspace/AGENTS.md` — these
  contain the full internal platform map and MUST be gitignored. The `workspace/`
  directory is in this repo's `.gitignore` to prevent accidental commits.
- **AWS resource IDs**: hardcoded bucket names, CloudFront distribution IDs,
  account IDs, role ARNs (even in comments)
- **Real credential values**: any token, key, or secret (even expired ones)

### Verification

Run the fleet-wide hygiene scan to catch private refs in public repos:

```bash
bash quality-kit/scripts/check-public-repo-hygiene.sh
```

The scan checks all repos whose remote points at `FelipeFuhr/` and prints
`[FAIL]` for any file containing known private identifiers.

### Fixing a leak

1. Replace private names with generic descriptions (see "What IS acceptable" above).
2. Check git history for the same string: `git log -p --all -S '<private-name>'`
3. If history contains the leak, use `git filter-repo --path <file> --invert-paths`
   or `git filter-repo --replace-text <expressions-file>` to purge all branches.
4. Force-push all affected branches (requires user confirmation for safety).
5. Run `git reflog expire --expire=now --all && git gc --prune=now` on the local clone.
6. Ask GitHub Support to run garbage collection on the remote if the leak was live.

