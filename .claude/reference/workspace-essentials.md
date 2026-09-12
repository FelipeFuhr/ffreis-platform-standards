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
