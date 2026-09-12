## What lives here

| Directory | Purpose |
|---|---|
| `renovate/` | Renovate preset files. Repos extend via `"github>FelipeFuhr/ffreis-platform-standards:renovate/<preset>"` |
| `lefthook/` | Shared lefthook hooks. Repos pull via `remotes:` in their `lefthook.yml` |
| `golangci/` | Reference golangci-lint v2 config. Go repos copy `golangci/standard.yml` to `.golangci.yml` |
| `flags/` | Canonical JSON Schema for the fleet's flag-registry convention (see below) |
