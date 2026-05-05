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

## Making fleet-wide changes

1. Update the relevant file in this repo
2. Open a PR — CI validates JSON/YAML/shell automatically
3. Merge to main
4. Renovate runs pick up changes fleet-wide; lefthook `remotes:` pulls on next `lefthook install`
