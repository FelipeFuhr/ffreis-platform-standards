---
paths:
  - "renovate/**"
  - "renovate.json"
---

# Renovate presets

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
