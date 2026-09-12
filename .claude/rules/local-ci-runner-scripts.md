---
paths:
  - "scripts/install_act.sh"
  - "scripts/run-ci-local.sh"
  - "scripts/ci-local.env.example"
---

# Local CI runner (`scripts/`)

Tooling for running GitHub Actions workflows locally via
[`act`](https://github.com/nektos/act). Intended as a fallback when GitHub
Actions monthly minutes are exhausted, **not** as a routine pre-commit
check (`make ci` is the routine check — see workspace `AGENTS.md`).

Two scripts, used together:

| Script | Purpose |
|---|---|
| `scripts/install_act.sh` | Downloads a pinned `act` binary into `.bin/act`. Mirrors the `lefthook/bootstrap_lefthook.sh` pattern (centralized version, fleet-wide consistency). Default: `ACT_VERSION=0.2.88`. |
| `scripts/run-ci-local.sh` | Self-contained `act` wrapper. Pins runner image inline (no external `.actrc` needed) so it works the same whether invoked directly or curl-downloaded into a repo. Auto-detects local credentials. |

### Per-repo Makefile snippet (recommended for active repos)

Paste this into a repo's `Makefile` — pattern mirrors how the lefthook
bootstrap is already pulled in (`.github/Makefile`, `ml/ffreis-integration-hub/Makefile`):

```makefile
PLATFORM_STANDARDS_SHA := <commit-sha>     # main as of YYYY-MM-DD
PLATFORM_STANDARDS_RAW := https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards

install-act: ## Download pinned act binary into .bin/
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/install_act.sh" \
		-o scripts/install_act.sh && chmod +x scripts/install_act.sh
	@bash ./scripts/install_act.sh

ci-local: ## Run workflows locally via act (GH Actions quota fallback)
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/run-ci-local.sh" \
		-o scripts/run-ci-local.sh && chmod +x scripts/run-ci-local.sh
	@PATH="$(CURDIR)/.bin:$(PATH)" bash ./scripts/run-ci-local.sh $(ARGS)
```

Pin `PLATFORM_STANDARDS_SHA` to a commit (not `main`) so script behavior
doesn't drift under you. The trailing comment documents what the SHA
corresponds to — Renovate keeps the SHA updated; humans update the comment
on the same PR.

After adding: `make install-act` once (caches the binary in `.bin/`), then
`make ci-local` (or `make ci-local ARGS=--quick`) any time.

### Alternative: shell alias (for cross-repo, no Makefile changes)

If you don't want to modify per-repo Makefiles, alias the script directly:

```bash
alias ci-local='bash /media/ffreis/second/projects/platform/ffreis-platform-standards/scripts/run-ci-local.sh'
```

Then `cd repo/ && ci-local`. Trades discoverability (no `make help` entry)
for zero per-repo churn.

### Credential auto-detection

The script never requires a credential — it passes through whatever it
finds and labels missing-secret failures separately from real failures.

| Source | Detected via | Passed as |
|---|---|---|
| AWS (env) | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` exported | `--secret AWS_*` |
| AWS (profile) | `aws sts get-caller-identity` with `AWS_PROFILE` (default `ffreis-platform`) | resolved via `aws configure export-credentials` (requires AWS CLI v2.13+) |
| GitHub token | `gh auth token` succeeds | `--secret GITHUB_TOKEN` |
| Anything else (reCAPTCHA, Sonar, …) | `~/.config/ffreis/ci-local.env` (user-managed, never committed) | `--secret KEY=VALUE` per line |

Template at `scripts/ci-local.env.example`. Copy to
`~/.config/ffreis/ci-local.env` (NOT into any repo) and fill in only
secrets you actually have locally.

### Prerequisites

- `act` installed — preferably via `install_act.sh` for fleet-pinned version
  (override with `ACT_VERSION` env var). Alternative: system package manager.
- Docker daemon running.
- Runner image (`ghcr.io/catthehacker/ubuntu:act-22.04`, ~500MB) pulls on
  first run. Override with `ACT_RUNNER_IMAGE` env var.

### Limits

- Won't replicate macOS matrix runners (`act` is Linux-only).
- Container builds run but GHCR push is blocked (no token).
- Anything depending on real GitHub API state (PR comments, scheduled
  triggers, environment approvals) won't execute meaningfully.

For deploy / promote / `tf-apply` workflows specifically: prefer waiting
for real CI to recover. The script does not block them, but a local
"success" doesn't mean the live deploy would succeed.
