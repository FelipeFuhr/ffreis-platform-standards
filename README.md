# ffreis-platform-standards

<!-- ffreis-badges:start -->
[![CI](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-platform-standards/ci.json)](https://github.com/FelipeFuhr/ffreis-platform-standards/actions) [![Latest version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-platform-standards/version.json)](https://github.com/FelipeFuhr/ffreis-platform-standards/releases) [![License](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-platform-standards/license.json)](https://github.com/FelipeFuhr/ffreis-platform-standards/blob/main/LICENSE)
<!-- ffreis-badges:end -->

Single source of truth for the shared development standards consumed across the
ffreis repo fleet: Renovate presets, lefthook hook configurations, a reference
golangci-lint config, and the local-CI / repo-parity tooling. Repos do not
copy-paste these configs — they consume them by **pinned reference** (lefthook
`remotes:`, Renovate `extends`), so a change here propagates fleet-wide once
released and re-pulled. The repo is self-referential: it runs its own
`lefthook/base.yml` + `lefthook/actionlint.yml` as a remote and pins its action
SHAs via its own `renovate.json`.

## What it provides

- **Renovate presets** (`renovate/`) — a base preset plus per-ecosystem presets.
  Consumers `extends` them by GitHub shorthand; per-ecosystem presets themselves
  extend `renovate/default`.
  - `default.json` — base: weekly schedule (`before 6am on Monday`),
    `prConcurrentLimit: 5`, `prHourlyLimit: 2`, `github-actions` minor/patch/digest
    automerge, major updates labeled and not auto-merged, plus custom managers that
    track `ffreis-platform-standards` and `ffreis-platform-ci-local` SHA/version pins
    in `Makefile`/`lefthook.yml`.
  - `go.json`, `python.json`, `python-pip.json`, `rust.json`, `terraform.json`,
    `github-actions.json` — enable the relevant managers (gomod / uv / pip /
    cargo / terraform) plus `dockerfile` + `github-actions`, with per-manager
    grouping.
- **Lefthook configs** (`lefthook/`) — shared git-hook definitions consumed via a
  `remotes:` block. All hook logic is inlined in the YAML (no per-repo
  `scripts/hooks/*.sh` needed). Three tiers:
  - `base.yml` — `pre-commit` hygiene (merge markers, large/binary files),
    staged secret-scan, AGENTS.md drift hint, staged actionlint + hadolint +
    ci-local-drift; `commit-msg` conventional-commits check; and the heavy
    `complex` / `release` named groups (whole-tree secret + OSV scans).
  - `go.yml`, `python.yml`, `rust.yml`, `terraform.yml` — language fmt-check /
    lint on `pre-commit`, plus `complex` (test/coverage/lint) and `release`
    (build / mutation / fuzz / plan / sec) commands. Every heavy command
    delegates to a Makefile target and **skips gracefully** when absent
    (`make -n` probe), so repos adopt the tiers incrementally.
  - `actionlint.yml` — optional actionlint hook for repos with significant
    workflow files.
  - `bootstrap_lefthook.sh` — per-repo bootstrap that downloads a pinned
    lefthook binary into `.bin/` (must stay per-repo; it runs before lefthook
    is installed, so it cannot be a remote).
- **golangci config** (`golangci/standard.yml`) — reference golangci-lint **v2**
  config. Go repos copy it to `.golangci.yml`; the only per-repo knob is
  `goimports.local-prefixes`.
- **Local-CI tooling** (`scripts/`) — an [`act`](https://github.com/nektos/act)
  wrapper for running GitHub Actions workflows locally when Actions minutes are
  exhausted (a fallback, not a routine check):
  - `install_act.sh` — downloads a fleet-pinned `act` binary into `.bin/`
    (`ACT_VERSION` default `0.2.88`).
  - `run-ci-local.sh` — self-contained act wrapper with auto-detected local
    credentials (AWS env/profile, `gh auth token`, `~/.config/ffreis/ci-local.env`).
  - `ci-local-findings.py`, `ci-local.env.example` — findings classifier and a
    credentials template (copy to `~/.config/ffreis/ci-local.env`, never commit).
- **Repo-parity checker** (`scripts/check-repo-parity.sh`) — audits a repo against
  its Copier template (resolved from `.copier-answers.yaml` `_src_path`, or
  `--template <name>`), reporting `MISSING:` paths present in the template but
  absent in the repo. Exit `0` at parity, `2` if any file is missing, `3` bad
  invocation, `4` no `.copier-answers.yaml` and no `--template`.

## How to consume

### Lefthook (per-repo `lefthook.yml`, Go example)

```yaml
remotes:
  - git_url: https://github.com/FelipeFuhr/ffreis-platform-standards
    ref: v1.0.0  # pin to a release tag; Renovate tracks updates
    configs:
      - lefthook/base.yml
      - lefthook/go.yml
```

That is the whole file. The remote brings the simple `pre-commit`/`commit-msg`
hooks plus the heavy `complex`/`release` groups. Do not add a per-repo
`pre-push: test` block — the heavy suite runs via
`lefthook run complex --all-files` at the draft→ready gate, not on every push.
`ref: main` always tracks latest; pin to a tag (`ref: v1.0.0`) for stability.
Run the `complex` / `release` groups explicitly:

```bash
lefthook run complex --all-files    # heavy suite (test/coverage/vuln) — at draft->ready
lefthook run release --all-files    # version-significant (build/mutation/fuzz) — minor/major bumps
```

### Renovate (per-repo `renovate.json`)

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>FelipeFuhr/ffreis-platform-standards:renovate/go"]
}
```

Pin to a released version for stability, and override limits where needed:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>FelipeFuhr/ffreis-platform-standards:renovate/go#v1.0.0"],
  "prConcurrentLimit": 3,
  "prHourlyLimit": 1
}
```

Available presets: `renovate/default`, `renovate/go`, `renovate/python`,
`renovate/python-pip`, `renovate/rust`, `renovate/terraform`,
`renovate/github-actions`.

### golangci (per Go repo)

Copy `golangci/standard.yml` to `.golangci.yml`; adjust
`goimports.local-prefixes` if the repo's import prefix differs from the default.

### Parity check

```bash
bash scripts/check-repo-parity.sh <repo-dir>            # autodetect template
bash scripts/check-repo-parity.sh --template go-cli <repo-dir>
```

## Layout

```
renovate/                 Renovate presets (default + per-ecosystem)
  default.json            base preset, extended by the rest
  go.json python.json python-pip.json rust.json terraform.json github-actions.json
lefthook/                 shared lefthook configs (consumed via remotes:)
  base.yml                hygiene + secret-scan + commit-msg + complex/release tiers (all repos)
  go.yml python.yml rust.yml terraform.yml   per-language fmt/lint + complex/release
  actionlint.yml          optional actionlint hook
  bootstrap_lefthook.sh   per-repo lefthook-binary bootstrap (not a remote)
  scripts/                inlined hook helper scripts
golangci/standard.yml     reference golangci-lint v2 config (copy to .golangci.yml)
scripts/
  check-repo-parity.sh    audit a repo against its Copier template
  install_act.sh          download pinned act binary into .bin/
  run-ci-local.sh         local GitHub Actions runner (act wrapper)
  ci-local-findings.py    classify local-CI findings
  ci-local.env.example    credential template for ~/.config/ffreis/ci-local.env
  bootstrap_lefthook.sh
lefthook.yml renovate.json   self-referential configs for this repo
Makefile                  validate-json / validate-yaml / lint / hooks / setup
AGENTS.md CHANGELOG.md LICENSE
.github/workflows/        ci.yml, release-please.yml, devops-*.yml
```

The Makefile exposes `make fmt-check` (lint + validate-json + validate-yaml),
`make shellcheck`, `make hooks` (bootstrap + install lefthook), and `make setup`.
CI (`ci.yml`) validates Renovate JSON, lefthook/golangci YAML, shell scripts
(shellcheck), and workflows (actionlint + CodeQL); release-please cuts versioned
tags when `vars.RELEASE_PLEASE_ENABLED == 'true'`.

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Felipe Fuhr.
