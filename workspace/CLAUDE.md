# Workspace Context — ffreis projects

This workspace root contains all personal and professional projects by Felipe Fuhr.
Each subdirectory is an independent git repo.

## Workspace Layout

| Directory | Contents |
|---|---|
| `ffreis-website*`, `ffreis-data*`, `flemming-*` | Static website fleet (see below) |
| `ffreis-website-inventory/` | Fleet registry — **start here for website fleet work** |
| `ffreis-website-deployer/` | CI/CD orchestrator for the website fleet |
| `ffreis-siteops/` | Local-dev CLI for website builds |
| `devops/ffreis-workflows-*/` | Reusable GitHub Actions workflow libraries |
| `platform/ffreis-project-templates/` | **Copier template library — start here for new repos** |
| `platform/ffreis-platform-*/` | Internal platform tooling (CLI, runner, infra, etc.) |
| `platform/ffreis-website-packer/` | S3 sync tool used by website CI/CD |
| `platform/ffreis-dynamoctl/` | DynamoDB table management CLI |
| `platform/ffreis-lambdas-packer/` | Lambda deployment packaging tool |
| `platform/ffreis-flemming-infra/` | Terraform infra for flemming.com.br |
| `website/ffreis-website-compiler/` | Go CLI that builds/validates static sites |
| `website/ffreis-website-lambdas-rust/` | Rust Lambda functions for websites |
| `ml/` | ML model serving and conversion pipeline |
| `stock/` | Stock simulator and related tools |
| `stock-rl-agent-repo/` | **Top-level** (not under `stock/`). RL trading agent. Depends on `stock/ffreis-agents-runtime` via a uv path source (`../stock/ffreis-agents-runtime`). |
| `k8s-platform/ffreis-mlflow/` | MLflow deployment on Kubernetes |
| `local-development/` | Vagrant-based local Kubernetes environments |
| `old/` | Archived repos — do not modify |
| `config/` | Workspace-level local dev configs (git-ignored, not in any repo) |
| `quality-kit/` | Shared workspace tooling (hooks, templates) — not a git repo |
| `_orphaned/` | **Ignore.** Abandoned, duplicate, and leftover items (see `_orphaned/AGENTS.md`) |

## Agent Safety Rules

These rules exist to prevent accidental production changes. They apply to every session,
every repo, and every tool call. Follow them without exception.

1. **NEVER push directly to `main` or `develop`.** Always create a feature branch and
   open a PR. Wait for CI to pass before merging. This is the single most important rule.

2. **NEVER run `terraform apply ENV=prod` without explicit user confirmation in the
   current session.** "Go ahead" from a previous message does not count. Ask again.

3. **NEVER dispatch a prod deployer workflow** (`website_name=flemming`, `petlook`, or
   `ffreis` without `-dev` suffix) without explicit user confirmation.

4. **When in doubt about environment (dev vs prod), always choose dev and ask.**
   `*-dev` inventory entries, `ENV=dev` make targets, and `develop` branches are always safe.
   `main`, `ENV=prod`, and bare site names (no `-dev`) affect real users.

5. **NEVER delete files from S3 live website buckets** (`*-website-prod`, `flemming-website`,
   `petlook-website-prod`, `ffreis-website-prod`) directly. Use the deployer pipeline.

6. **Before any `terraform plan` or `terraform apply`**, confirm the backend matches the target
   ENV. Run `make validate-state ENV=<env>` (petlook-infra, flemming-infra) or check
   `terraform state list | head -3` shows resources matching the intended environment.
   State contamination (dev resources in prod state) causes 100+ spurious replacements.

## Rules for Every Session

1. **Read repo AGENTS.md first.** Every repo has an `AGENTS.md` at its root. Before
   editing files in a repo, read that file. It contains non-obvious constraints,
   cross-repo dependencies, and conventions that are not derivable from the code.

2. **Website fleet work: start with the inventory.** For anything touching websites,
   read `ffreis-website-inventory/AGENTS.md` before anything else. It maps all
   component interactions, flows, and secrets.

3. **Subagents must include repo AGENTS.md.** When spawning a subagent (via Agent
   tool) to work on a specific repo, always include that repo's `AGENTS.md` content
   in the agent prompt. Subagents do not auto-load it.

4. **`old/` and `_orphaned/` are archived.** Never suggest changes to anything under `old/` or `_orphaned/`.

5. **`config/` is git-ignored workspace config.** Files here (e.g.,
   `config/ffreis.local.yaml`) are local dev configs, not committed to any repo.
   They contain local paths and may reference local binaries.

6. **New repo? Use Copier from `platform/ffreis-project-templates/` first.**
   Before `git init` or `mkdir <new-repo>`, check
   `platform/ffreis-project-templates/templates/` for a matching template:
   `terraform-infra`, `go-cli`, `rust-lambda`, `python-service`,
   `knowledge-base`, `github-actions-lib`. If one fits, scaffold via
   `copier copy gh:FelipeFuhr/ffreis-project-templates --subdirectory templates/<name> <target-dir>`.
   Hand-rolling a repo without checking the templates is a maturity-debt
   anti-pattern (the dashboard-infra 10-PR retrofit, 2026-05-26, was caused
   by this miss). For existing repos without `.copier-answers.yaml`,
   backfill one so `copier update` works and
   `platform/ffreis-platform-standards/scripts/check-repo-parity.sh <repo>` can audit drift.
   Full agent-agnostic version of this rule lives in [AGENTS.md](AGENTS.md).

## Disk + memory safety for heavy builds

`/media/ffreis/second` is the projects volume and is shared across all Rust,
Go, and Terraform work. Cargo lambda builds in `petlook-lambdas-rust/lambdas/`
and `website/ffreis-website-lambdas-rust/lambdas/` each consume 15–18 GB of
target artifacts and peak 15+ GB of RAM at default rustc parallelism.
Multiple 2026-05-22..23 sessions filled the disk to 0 bytes (or OOM-killed
the desktop session) mid-build.

Both heavy-build Makefiles (`petlook-lambdas-rust`, `website/ffreis-website-lambdas-rust`)
already call these guards in their `build` / `package` / `package-one` targets:

```bash
bash quality-kit/scripts/check-disk.sh   # default threshold: 10 GB free
bash quality-kit/scripts/check-mem.sh    # default threshold: 6 GB available
```

They also export `CARGO_BUILD_JOBS=4` (down from the default of one job per
CPU, ~16) to cap rustc parallelism. Override with `CARGO_BUILD_JOBS=N` if
you have headroom.

If you only need one lambda zip, prefer `make package-one CRATE=<name>` over
`make package` — peaks ~4 GB instead of ~15 GB.

Recovery when disk or RAM is tight:
```bash
cd <rust-repo>/lambdas && cargo clean       # 1–18 GB per repo
rm -rf <infra-repo>/infra/.terraform        # 0.7–1.6 GB; will re-init
podman system prune -af                     # container cache
```

Never run a `cargo lambda build` or `cargo build --release` directly (bypassing
make) without first calling `check-disk` and `check-mem` — a single such build
can swing free space by 15+ GB and OOM the desktop session.

## Pre-commit validation

Before proposing or making a `git commit` in any repo you touched, run a local
check to catch the trivial failures that would otherwise burn GitHub Actions
minutes (the workspace shares a finite monthly quota across 71+ repos):

```bash
make ci                  # fmt-check + lint + test + sec (the standard)
make lint && make test   # fallback if `make ci` is not defined in the repo
```

If neither exists, note it in your response rather than committing untested.

When GitHub Actions quota is exhausted entirely, the human user can run the
actual workflows locally via `act`:
`bash platform/ffreis-platform-standards/scripts/run-ci-local.sh`. Do not
invoke this unprompted — it's an out-of-band fallback, not part of the
normal commit flow.

Agent-agnostic version of this guidance lives in [AGENTS.md](AGENTS.md).

## Website Fleet Quick Reference

The static website fleet is documented in full in `ffreis-website-inventory/AGENTS.md`.
Short version:

- **ffreis-website-deployer** — CI/CD pipeline (reads inventory, builds, deploys to S3)
- **ffreis-siteops** — local-dev CLI wrapping the compiler; NOT used in CI/CD
- **ffreis-website-compiler** — Go build/validate CLI used by both siteops and CI/CD
- **ffreis-website** + **ffreis-data** — templates and content for ffreis.com
- **flemming-website** + **flemming-data** — templates and content for flemming.com.br
- **ffreis-website-inventory** — one YAML per website; source of truth for CI/CD config

## GitHub Actions CI policy

All workflows in this fleet follow the standards documented in
`platform/ffreis-platform-standards/AGENTS.md` (section "GitHub Actions CI standards").
When adding or reviewing any `.github/workflows/` file, enforce:

1. `concurrency.cancel-in-progress: true` on every push/PR workflow.
2. `timeout-minutes` on every **direct** job (15 min for quick checks, 30 min for builds/tests).
3. No `timeout-minutes` on `uses:` caller jobs — GitHub Actions forbids it; set the timeout
   inside the reusable workflow definition instead.
4. `if: ${{ !github.event.pull_request.draft }}` on expensive jobs in PR-triggered workflows.
5. `permissions:` per job, least privilege. **No top-level `permissions:` block.** See
   `platform/ffreis-platform-standards/AGENTS.md` § "Per-job permissions" for patterns.
6. Path filters (`on.push.paths`, `on.pull_request.paths`) on workflows that only
   need to run when specific files change. Conserves the shared CI minutes budget.

## Go test invariant

Every Go module's `make test` target runs `go test -race -shuffle=on ./...` (some include
`-v -count=1` on top). The `-shuffle=on` flag catches test-order coupling and shared global
state; `-race` catches data races. When adding new Go modules or new Makefile test targets,
preserve both flags.

One exception is documented in-line: `platform/ffreis-platform-runner/Makefile` omits
`-shuffle=on` because its cmd/ tests use a `captureStdout` helper that swaps the process
`os.Stdout`, racing with `t.Parallel()` tests in the same package. Restore `-shuffle=on`
there once `captureStdout` is made concurrency-safe.

## Keeping context files current

- Before finishing any task in a repo, check if that repo's `AGENTS.md` needs updating.
- If you discover undocumented facts, add them to the appropriate `AGENTS.md`.
- Fleet-level changes go in `ffreis-website-inventory/AGENTS.md`.
- Subagent prompts must include the relevant `AGENTS.md`; update it there too if you learned something new.

## AWS Access

Static credentials live in `~/.aws/credentials` (profile `ffreis-platform-base`) and
`~/.aws/config` (profile `ffreis-platform` assumes role `platform-admin` from the base profile).

**When the user says "aws api key available"** (or any equivalent like "credentials are set"):
- Do NOT run `aws login` — that opens a browser OAuth flow that cannot complete in this environment.
- Use `AWS_PROFILE=ffreis-platform` for all AWS CLI calls (the role profile, not the base profile).
- Example: `AWS_PROFILE=ffreis-platform aws s3 ls s3://my-bucket/`
- If `AWS_PROFILE=ffreis-platform` returns `AccessDenied`, the direct user (`ffreis-admin`) lacks
  the permission — use the role profile which assumes `platform-admin`.
