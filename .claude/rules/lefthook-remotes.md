---
paths:
  - "lefthook/**"
  - "lefthook.yml"
---

# Lefthook remotes

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
- `lefthook/go.yml` — go-mod-drift + fmt-check + lint; `complex`: quality-gates + integration-coverage; `release`: cross-build + mutation + fuzz
- `lefthook/python.yml` — fmt-check (Python glob); `complex`: lint (ruff+mypy) + test/coverage + integration-coverage; `release`: mutation
- `lefthook/rust.yml` — fmt-check (Rust glob); `complex`: lint (clippy) + test + sec + integration-coverage; `release`: release-build + mutation-diff (DIFF-scoped — see "Mutation testing: PR-time vs scheduled")
- `lefthook/terraform.yml` — fmt-check + tflint lint (Terraform glob); `complex`: validate; `release`: plan + sec (tfsec)
- `lefthook/ansible.yml` — yamllint (Ansible dirs: `ansible/`, `playbooks/`, `roles/`); `complex`: lint (ansible-lint); `release`: dry-run + sec (ansible-lint --profile production)
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

Every `complex`/`release` command delegates to a Makefile target, and since #62 **every
referenced target is REQUIRED** — adding a language's config to a repo's lefthook
`remotes:` is a commitment that the repo implements every target that config's tiers
call (`quality-gates`/`mutation`/`coverage-gate`/`integration-coverage-gate`/`build-all`/
etc., depending on language). There is no `make -n <target>` skip probe anymore: a
missing target fails the group with "No rule to make target" the same as a target that
*exists and fails*, blocking `/ready`. Repos pin a specific `ref:` SHA/tag, so this only
bites when a repo deliberately bumps its pin — **implement every target the new tier
calls in the same PR that bumps the pin**, don't bump and hope. There is intentionally
**no `pre-push` standard** — in the draft-first flow pushes are frequent; heavy work
belongs at the promotion gate.

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
