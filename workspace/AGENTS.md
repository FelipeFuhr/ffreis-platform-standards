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

## Tagging — single source of truth

Every AWS resource MUST get its tags from
[`platform/ffreis-platform-terraform-modules/modules/tagging` v2.0.0+](platform/ffreis-platform-terraform-modules/modules/tagging).
Do not invent a new `default_tags` block; do not hand-roll per-resource tag maps.
The module enumerates the required schema (`Project`, `Environment`, `Stack`,
`Layer`, `CostCenter`, `Lifecycle`, `FixedCostTier`, `Domain`, …) and validates
the enums so Cost Explorer queries stay consistent across the fleet.

Pattern:

```hcl
module "tags" {
  source = "git::https://github.com/FelipeFuhr/ffreis-platform-terraform-modules.git//modules/tagging?ref=v2.0.0"

  project          = "flemming"
  environment      = var.environment
  stack            = "flemming"
  layer            = "flemming-infra"
  terraform_repo   = "ffreis-flemming-infra"
  terraform_root   = "infra"
  cost_center      = "flemming"                  # per-product, not "engineering"
  domain           = "flemming.com.br"
  lifecycle_state  = var.environment == "prod" ? "production" : "development"
  fixed_cost_tier  = "low"
}

provider "aws" {
  default_tags { tags = module.tags.tags }
}
```

Per-resource override: `tags = merge(module.tags.tags, { Lifecycle = "experiment" })`.

The `CostCenter` value MUST be per-product (`flemming`, `petlook`, `ffreis-website`,
`platform`, `dashboard`, `ai-ask`). A single shared value like `engineering` defeats
the purpose — Cost Explorer can't split spend per product.

## Fixed-cost discipline

Default principle: every AWS resource should be pay-per-request. Fixed monthly
costs require explicit justification.

**Before merging any PR that adds an `aws_*` resource, author (or agent) must:**

1. Quote the resource's fixed monthly cost in the PR body or a comment in the
   `.tf` file. If zero, say `$0 — pay-per-request only`.
2. Set the `FixedCostTier` tag honestly (`none` / `low` / `medium` / `high`).
3. If `medium` or `high`: justify why the pay-per-request alternative isn't
   suitable, and check whether an existing resource can be reused or shared.

**Known fixed-cost services** (non-exhaustive — extend on first use):

| Service | Fixed cost | Cheaper alternative |
|---|---|---|
| `aws_wafv2_web_acl` | $5/mo per ACL + $1/mo per rule | CloudFront geo/CIDR restrictions; share one ACL across distributions |
| `aws_cloudwatch_metric_alarm` | $0.10/mo each | Use `for_each` over a single set, not copy-paste |
| `aws_kms_key` | $1/mo each | AES256 / AWS-owned key |
| `aws_nat_gateway` | $32/mo each + data | VPC endpoints; NAT instance in non-prod |
| `aws_route53_zone` | $0.50/mo each | Reuse an existing zone with subdomains |
| `aws_lb` (ALB) | $16/mo each | API Gateway / CloudFront |
| `aws_db_instance`, `aws_elasticache_cluster`, Lambda provisioned concurrency | Case-by-case | DDB on-demand; Aurora Serverless v2 scales to zero |

**Soft cap**: any single PR adding > $5/mo of fixed cost must list the cost in
the PR title (e.g. `[+$10/mo] add WAF ACL for petlook`).

The four infra repos (`petlook-infra`, `ffreis-website-infra`,
`ffreis-platform-shared-infra`, `ffreis-flemming-infra`) run `infracost` on
every PR — the comment posted by the bot is the authoritative $/month delta.
Read it before approving merge.

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
