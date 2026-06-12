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
```
That's the whole file. The remotes bring the simple `pre-commit`/`commit-msg` hooks AND
the heavy `complex`/`release` groups. Do **not** add a per-repo `pre-push: test` block —
the heavy suite now runs via `lefthook run complex --all-files` at the draft→ready gate
(`/ready`), not on every push (see the tier section below). A repo only adds local
overrides when it genuinely diverges (e.g. a chdir for a non-standard layout).

Available shared configs:
- `lefthook/base.yml` — hygiene (merge markers, large files, binary files) + secret-scan + agents-drift-hint + commit-msg (ALL repos); plus the `complex`/`release` heavy tiers (see below)
- `lefthook/go.yml` — go-mod-drift + fmt-check + lint; `complex`: quality-gates; `release`: cross-build + mutation + fuzz
- `lefthook/python.yml` — fmt-check (Python glob); `complex`: lint (ruff+mypy) + test/coverage; `release`: mutation
- `lefthook/rust.yml` — fmt-check (Rust glob); `complex`: lint (clippy) + test + sec; `release`: release-build + mutation
- `lefthook/terraform.yml` — fmt-check + tflint lint (Terraform glob); `complex`: validate; `release`: plan + sec (tfsec)
- `lefthook/actionlint.yml` — actionlint on GitHub Actions workflows (optional, add for repos with significant workflow files)

### Simple vs complex/release tiers

There are three categories of checks, defined once here and run identically by the
local git hooks and by CI (via `general-lefthook.yml`):

- **SIMPLE** = the `pre-commit` + `commit-msg` stages. Fast (<~30s), run on *staged
  files* automatically on every commit, and as the always-on CI fail-fast gate. Never
  removed, never skipped.
- **COMPLEX (tier-1)** = the `complex` named group. The standard heavy suite (test, race,
  coverage, vuln/clippy). NOT a git hook — invoke explicitly with
  `lefthook run complex --all-files`. Run locally before a draft→ready promotion
  (`/ready` does this automatically) and as the manual `workflow_dispatch` CI step.
- **RELEASE (tier-2)** = the `release` named group. Version-significant verification
  (cross-build / release-build, mutation, fuzz, deep dependency scans, terraform plan).
  Run **in addition to** complex, only when the branch's conventional commits imply a
  **minor or major** bump (`quality-kit/scripts/semver-bump.sh` decides). Invoke with
  `lefthook run release --all-files`.

Every `complex`/`release` command delegates to a Makefile target and **skips gracefully**
when that target is absent (a `make -n <target>` existence probe), so repos can adopt the
tiers incrementally — a missing `mutation`/`coverage`/`build-all` target prints `skip:`
and the group keeps going. A target that *exists and fails* fails the group (so the
`/ready` gate blocks). There is intentionally **no `pre-push` standard** — in the
draft-first flow pushes are frequent; heavy work belongs at the promotion gate.

**Staged vs `--all-files` (important, non-obvious):** the `base.yml` simple hooks read the
git *index* (`git diff --cached`), so `--all-files` is a no-op for them. CI achieves
full-repo parity by **staging everything first** (`general-lefthook.yml` does `git add -A`,
`stage-files: true`) — *not* by passing `--all-files`. Do **not** "fix" the CI simple job
to use `--all-files`; it silently reverts to partial coverage. The `complex`/`release`
groups are Makefile-target based (whole tree), so `--all-files` *is* meaningful there and
is required when invoking them in CI or `/ready`.

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

## Coverage and test-type standards

Fleet-wide minimums (enforced via `make coverage-gate` in the `complex` lefthook tier):

| Language | Min coverage | Tool | Integration tests | Property tests | Mutation threshold |
|---|---|---|---|---|---|
| Go | 75% | `go test -coverprofile` + `check_coverage_gate.sh` | `//go:build integration` test files for service-boundary code | optional | 60% (gremlins) |
| Rust | 75% | cargo-llvm-cov (line coverage) | `tests/` per crate for service ports | proptest recommended | 60% (cargo-mutants) |
| Python | 75% (branch) | pytest-cov (`fail_under`) | separate `tests/integration/` | hypothesis recommended | 60% (mutmut) |

New repos must set a `coverage-gate` Makefile target that enforces at least the floor above.
The Copier project templates include this target by default.

Mutation testing runs in the `release` tier only — it is expensive and scheduled (weekly CI),
not a pre-push gate. A missing `mutation` target is a graceful skip, not a failure.

The complex tier's `coverage` command (rust.yml) and `quality-gates` target (go.yml) both
skip gracefully when the Makefile target is absent — adopt incrementally.

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
| Draft gate on **every** PR job (not just expensive ones) | `if: ${{ github.event_name != 'pull_request' \|\| github.event.pull_request.draft == false }}` — or call a fleet reusable workflow, which carries the gate | Drafts run ~no CI; see "Draft gating" below |
| `on.pull_request.types: [opened, synchronize, reopened, ready_for_review]` | Every PR-triggered workflow | So promoting a draft to ready fires CI natively (the bare default omits `ready_for_review`) |
| `permissions:` per job (least privilege) | Required, **no workflow-level `permissions:`** | See "Per-job permissions" below |
| Path filters on push/PR triggers | Required where applicable | Limit triggers to files that actually affect the workflow |

### Draft gating (no CI on draft)

Draft PRs must run ~no CI; full CI runs only when a PR is **ready for review** and on
**push to `main`/`develop`**. Enforced by `general-workflows-policy.yml` (fleet) and
`quality-kit/scripts/audit-ci-standards.sh` (local).

Two required pieces on every PR-triggered workflow:

1. **Trigger** — list `ready_for_review` so promotion fires CI:
   ```yaml
   on:
     pull_request:
       types: [opened, synchronize, reopened, ready_for_review]
   ```
   Adding an explicit `types:` replaces the default set, so you MUST re-list
   `opened, synchronize, reopened` alongside `ready_for_review`.

2. **Job guard** — every PR job either calls a fleet reusable workflow (which carries the
   gate) or guards itself:
   ```yaml
   jobs:
     lint:
       if: ${{ github.event_name != 'pull_request' || github.event.pull_request.draft == false }}
   ```
   On `push` the guard short-circuits to true (no draft concept on push), so push CI is
   unaffected.

**`needs:` cascade:** put the guard on the **root** job (the one with no `needs:`). When a
gated job skips on a draft, downstream jobs that `need:` it skip too (the default
success requirement) — so guarding the root skips the whole chain. Do **not** add
`if: always()`; that defeats the skip.

**Tuning knobs** (default = skip on draft): reusable workflows expose a `run_on_draft`
boolean input (default `false`) and honour a repo variable `vars.CI_RUN_ON_DRAFT == 'true'`.
To run a cheap lane (e.g. fmt/lint) on drafts, pass `run_on_draft: true` to that caller job,
or set the repo variable to opt the whole repo in — no other YAML change.

**Exempt** workflows (release, scheduled drift, scorecard, security-always-run) are not
draft-gated; list them in the `draft-gate-exempt` input of `general-workflows-policy.yml`.

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
- **Each carries the draft gate** so the whole fleet inherits it from one place: a
  `run_on_draft` boolean input (default `false`) plus, on the root job,
  `if: ${{ inputs.run_on_draft || vars.CI_RUN_ON_DRAFT == 'true' || github.event_name != 'pull_request' || github.event.pull_request.draft == false }}`.
  Callers then get "no CI on draft" with no per-job `if:`; pass `run_on_draft: true` to opt
  a cheap job (e.g. fmt) back into running on drafts.

### CI cost control

The fleet shares a finite monthly Actions-minutes budget across 80+ repos. The goal is
**not less CI** — it is full CI *at the gates that matter* (promotion to ready, push to a
default branch) and *~zero CI on work-in-progress*. Beyond the structural rules above,
every workflow respects these spend levers:

| Lever | Rule | Why |
|---|---|---|
| **Draft gating** | PR jobs skip on draft (per-job `if:` guard, or call a fleet reusable that carries the gate); `on.pull_request.types` lists `ready_for_review` so promotion fires CI | A Claude/agent-driven PR is pushed many times while still a draft — full CI on each push burns the budget. |
| **Bounded `push:`** | Every `push:` trigger sets `branches:` (normally `[main]`, or `[main, develop]`) | An unbounded `on: push` runs full CI on *every* feature-branch push, double-billing what the draft PR already gates. **Fleet target + current state: zero unbounded `push:` triggers.** |
| **Scanner tiering** | Heavy scanners (CodeQL, semgrep, scorecards, snyk, lighthouse, a11y, SEO, mutation, fuzz) run on `schedule:` and/or push-to-default — **never** on every draft PR | These are the priciest jobs; a nightly/weekly cadence on the merged tree gives the coverage without per-WIP cost. |
| **Required-check safety** | A required status check must always *run and report* — never `skip`. A check that is sometimes irrelevant (e.g. a promote-gate on a CI-only PR) must still run and **pass** (detect "nothing to do" → exit 0), not be skipped | A skipped required check reads as "unsatisfied" and wedges merge; the wrong fix is then weakening branch protection. Run-and-pass keeps protection intact. See `general-promote-gate.yml`'s CI-only-change short-circuit. |
| **Cron jitter** | New scheduled workflows pick a per-repo/per-workflow minute+hour, not a shared round value | Many repos currently share `0 6 * * 1` (security) / `0 3 * * 0` (automation). GitHub **queues** simultaneous crons — so this is queue latency, *not* extra minutes — but jittering (`<repo-hash % 60> <6..9> * * 1`) smooths the herd. Low priority precisely because it does not change billing. |

**Self-enforcing, no drift:** the draft-gating + `ready_for_review` + concurrency rules are
asserted on every PR by `general-workflows-policy.yml`; the local mirror is
`quality-kit/scripts/ci_draft_policy.py` (`make -C quality-kit ci-standards`). New repos
inherit the gated, structured workflows from the Copier templates
(`platform/ffreis-project-templates`) — **fix the template, not 80 copies** — so the standard
cannot be missed on a newly-scaffolded repo.

**Proactive backstops against a sudden burst** (two layers, set both):
1. **Hard ceiling** — the GitHub billing **spending limit** (Settings → Billing → Spending
   limit). A runaway loop physically cannot exceed it. This is the only true cap; set it.
2. **Early warning** — the `ffreis-platform-monitor-lambda` Actions-burst alert emails when
   fleet-wide workflow-run volume spikes past a tunable threshold in a short window
   (`ACTIONS_BURST_THRESHOLD` / `ACTIONS_BURST_WINDOW_MIN`), so a spike is caught long before
   it reaches the ceiling.

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

**Merge strategy — one rule per PR type (enforced, not advisory):**

| PR type | Merge strategy | Why |
|---|---|---|
| `feature/*` → `develop` | **Squash** | Each feature = one commit; keeps develop history linear |
| `develop` → `main` (promote) | **Merge commit** | Preserves develop as a parent of main's HEAD |
| `main` → `develop` (sync) | **Merge commit** | Records ancestry; makes next sync a clean fast-forward |

**Why merge commit for promote/sync?** Squash-merges have only one parent (the base branch). Without develop as a parent of main's merge commit, the next main→develop merge has no clean common ancestor, and git re-opens every conflict that was resolved in the promote. With a merge commit, develop IS a parent of main — so the sync-back is always a conflict-free fast-forward. Rebase has the same ancestry-loss problem as squash and additionally requires force-pushing develop.

Repos allow both merge commit and squash (set by `configure-repo-settings.sh`). When merging a promote or sync PR, use the **"Create a merge commit"** option in GitHub's merge button dropdown, or `gh pr merge <N> --merge`.

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
# Merge with MERGE COMMIT: gh pr merge <N> --merge  (not --squash)
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

