# Workspace Agent Guide

Agent-agnostic rules for any AI coding assistant (Claude Code, Codex, Cursor, …)
working in this workspace. Mirrors [CLAUDE.md](CLAUDE.md), which is the
Claude-specific entry point — keep them in sync when adding rules.

This workspace root contains all personal and professional projects by Felipe Fuhr.
Each subdirectory is an independent git repo. See [CLAUDE.md](CLAUDE.md) for the
full workspace layout table.

## Agent Safety Rules

These prevent accidental production changes. Apply to every session, every repo,
every tool call. No exceptions.

1. **NEVER push directly to `main` or `develop`.** Create a feature branch, open
   a PR, wait for CI to pass before merging.
2. **NEVER run `terraform apply ENV=prod` without explicit user confirmation in
   the current session.** "Go ahead" from earlier does not count — ask again.
3. **NEVER dispatch a prod deployer workflow** (`website_name=flemming`,
   `petlook`, or `ffreis` without `-dev`) without explicit user confirmation.
4. **When in doubt about environment (dev vs prod), choose dev and ask.**
   `*-dev`, `ENV=dev`, and `develop` are safe; `main`, `ENV=prod`, and bare
   site names affect real users.
5. **NEVER delete from S3 live website buckets** directly. Use the deployer.
6. **Before any `terraform plan`/`apply`**, confirm the backend matches the
   target ENV (`make validate-state ENV=<env>` or
   `terraform state list | head -3`).

## Rules for Every Session

1. **Read repo `AGENTS.md` first.** Every repo has one; it documents
   non-obvious constraints, cross-repo dependencies, and conventions.
2. **Website fleet work: start with the inventory.** Read
   `ffreis-website-inventory/AGENTS.md` first.
3. **Subagents must include repo `AGENTS.md`.** When spawning a subagent for
   a specific repo, include that repo's `AGENTS.md` in the prompt.
4. **`old/` and `_orphaned/` are archived.** Never modify them.
5. **`config/` is git-ignored workspace config.** Local dev only.
6. **New repo? Use Copier from `platform/ffreis-project-templates/` first.**
   Before `git init` or `mkdir <new-repo>`, check
   `platform/ffreis-project-templates/templates/` for a matching template
   (current options: `terraform-infra`, `go-cli`, `rust-lambda`,
   `python-service`, `knowledge-base`, `github-actions-lib`). If one fits,
   scaffold via:
   ```bash
   copier copy gh:FelipeFuhr/ffreis-project-templates \
     --subdirectory templates/<name> <target-dir>
   ```
   Hand-rolling a repo without checking the templates is a maturity-debt
   anti-pattern (see the dashboard-infra 10-PR retrofit, 2026-05-26 — every
   one of Makefile, CI workflows, lefthook, renovate, release-please, Go CLI,
   IAM roles, and the parity docs themselves had to be added after the fact
   because the original `mkdir` skipped the template).

   For an **existing** repo that was hand-rolled (no `.copier-answers.yaml`),
   backfill one so future `copier update` runs work and so
   `platform/ffreis-platform-standards/scripts/check-repo-parity.sh` can report drift against the
   template.

## Auditing existing repos for template parity

`bash platform/ffreis-platform-standards/scripts/check-repo-parity.sh <repo-dir>` reports template
drift for any repo with a `.copier-answers.yaml`. Files present in the
template but missing from the repo print as `MISSING:`; the script exits
non-zero if any are missing so it can be wired into CI or a workspace-level
audit. Run it ad-hoc when investigating "does this repo match the template?"

## Pre-commit validation (cheap local CI)

GitHub Actions minutes are finite and shared across 71+ repos. Before
proposing or making a `git commit` in any repo you touched, run a fast
local check to catch the trivial failures that would otherwise burn CI
minutes:

```bash
make ci          # standardized target: fmt-check + lint + test + sec
```

If `make ci` does not exist in the touched repo, fall back to:

```bash
make lint && make test
```

If neither target exists, the repo predates the standard — note it in your
response so the user can decide whether to add one.

**This is not optional**: every commit should be preceded by a local
validation pass. It takes seconds-to-minutes per repo and catches the
overwhelming majority of CI failures (formatting drift, lint regressions,
broken unit tests, missing `go mod tidy`).

## Local CI fallback (when GitHub quota is hit)

When GitHub Actions minutes are exhausted, the workspace ships a wrapper
around [`act`](https://github.com/nektos/act) that runs the actual
`.github/workflows/*.yml` locally in Docker:

```bash
bash platform/ffreis-platform-standards/scripts/run-ci-local.sh           # full
bash platform/ffreis-platform-standards/scripts/run-ci-local.sh --quick   # lint/test only
```

Run it from inside the target repo. The script auto-detects local
credentials (AWS via `AWS_PROFILE`, GitHub via `gh auth token`, extras via
`~/.config/ffreis/ci-local.env`) and labels missing-credential failures
separately from real test failures. Details and credential contract:
[platform/ffreis-platform-standards/AGENTS.md](platform/ffreis-platform-standards/AGENTS.md).

Agents: do **not** invoke `run-ci-local.sh` unprompted. It's an
out-of-band tool for the human user when GitHub CI is unavailable; agents
should always prefer the standard `make ci` flow.

## AWS Access

Static credentials live in `~/.aws/credentials` (profile
`ffreis-platform-base`) and `~/.aws/config` (profile `ffreis-platform`
assumes role `platform-admin`).

When the user says "aws api key available" (or equivalent):
- Do NOT run `aws login` — it opens a browser OAuth that can't complete here.
- Use `AWS_PROFILE=ffreis-platform` for all AWS CLI calls (the role profile).
- If `AccessDenied`, the direct user lacks the permission — use the role
  profile which assumes `platform-admin`.

## Keeping context files current

- Before finishing any task in a repo, check if its `AGENTS.md` needs updating.
- Undocumented facts you discover: add them to the appropriate `AGENTS.md`.
- Fleet-level changes go in `ffreis-website-inventory/AGENTS.md`.
- Workspace-level rules belong here (and mirrored to `CLAUDE.md`).
