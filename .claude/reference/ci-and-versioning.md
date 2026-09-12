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
