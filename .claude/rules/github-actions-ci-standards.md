---
paths:
  - ".github/workflows/**"
---

# GitHub Actions CI standards

All `.github/workflows/*.yml` files in the fleet follow these rules. Apply to every
new workflow and every edit to an existing one.

### Required structural elements

| Element | Rule | Notes |
|---|---|---|
| `concurrency.cancel-in-progress: true` | Every push/PR workflow | Prevents stale runs racing with new commits |
| `timeout-minutes` per job | Every **direct** job | 15 min for quick checks, 30 min for builds/tests; never omit |
| `timeout-minutes` on `uses:` caller jobs | **Forbidden** (GitHub rejects) | Set the timeout inside the reusable workflow's job instead |
| Draft gate on **every** PR job (not just expensive ones) | `if: ${{ github.event_name != 'pull_request' \|\| github.event.pull_request.draft == false }}` — or call a fleet reusable workflow, which carries the gate | Drafts run ~no CI; see "Draft gating" below |
| `on.pull_request.types: [opened, synchronize, reopened, ready_for_review]` | Every PR-triggered workflow | So promoting a draft to ready fires CI natively (the bare default omits `ready_for_review`) |
| `permissions:` per job (least privilege) | Required, **no workflow-level `permissions:`** | See "Per-job permissions" below |
| Path filters on push/PR triggers | Required where applicable | Limit triggers to files that actually affect the workflow |

### Draft gating (no CI on draft)

Draft PRs must run ~no CI; full CI runs only when a PR is **ready for review** and on
**push to `main`/`develop`**. Enforced by `general-workflows-policy.yml` (fleet) and
`quality-kit/scripts/audit-ci-standards.sh` (local).

Two required pieces on every PR-triggered workflow:

1. **Trigger** — list `ready_for_review` so promotion fires CI:
   ```yaml
   on:
     pull_request:
       types: [opened, synchronize, reopened, ready_for_review]
   ```
   Adding an explicit `types:` replaces the default set, so you MUST re-list
   `opened, synchronize, reopened` alongside `ready_for_review`.

2. **Job guard** — every PR job either calls a fleet reusable workflow (which carries the
   gate) or guards itself:
   ```yaml
   jobs:
     lint:
       if: ${{ github.event_name != 'pull_request' || github.event.pull_request.draft == false }}
   ```
   On `push` the guard short-circuits to true (no draft concept on push), so push CI is
   unaffected.

**`needs:` cascade:** put the guard on the **root** job (the one with no `needs:`). When a
gated job skips on a draft, downstream jobs that `need:` it skip too (the default
success requirement) — so guarding the root skips the whole chain. Do **not** add
`if: always()`; that defeats the skip.

**Tuning knobs** (default = skip on draft): reusable workflows expose a `run_on_draft`
boolean input (default `false`) and honour a repo variable `vars.CI_RUN_ON_DRAFT == 'true'`.
To run a cheap lane (e.g. fmt/lint) on drafts, pass `run_on_draft: true` to that caller job,
or set the repo variable to opt the whole repo in — no other YAML change.

**Exempt** workflows (release, scheduled drift, scorecard, security-always-run) are not
draft-gated; list them in the `draft-gate-exempt` input of `general-workflows-policy.yml`.

### Per-job permissions

GitHub's `permissions:` block grants scopes to the `GITHUB_TOKEN`. The default if omitted
varies by repo settings — never rely on the default.

Two rules:

1. **No top-level `permissions:` block.** Top-level grants apply to every job, which
   over-grants for jobs that don't need write access. Declare per job instead.
2. **Each job declares exactly what it needs**, read-only by default. Write scopes
   (e.g. `contents: write`, `pull-requests: write`) only on the specific job that
   performs the write.

Common patterns:

```yaml
jobs:
  test:
    timeout-minutes: 15
    permissions:
      contents: read           # checkout only
    runs-on: ubuntu-latest
    steps: ...

  codeql:
    timeout-minutes: 30
    permissions:
      contents: read
      security-events: write   # upload SARIF
      actions: read
    runs-on: ubuntu-latest
    steps: ...

  release:
    timeout-minutes: 15
    permissions:
      contents: write          # create tag/release
      pull-requests: write     # release-please PRs
    runs-on: ubuntu-latest
    steps: ...
```

For jobs that only call a reusable workflow (`uses:`):

```yaml
jobs:
  call-go-test:
    permissions:
      contents: read
    uses: FelipeFuhr/ffreis-workflows-go/.github/workflows/go-test.yml@v1
```

The caller's per-job permissions become the `GITHUB_TOKEN` scope inside the reusable
workflow. Reusable workflows in this fleet **also** declare per-job permissions
internally as defense-in-depth — callers should still pass the minimal set explicitly.

### Path filters

Workflows that only need to run when specific files change should declare path filters
on `push:` and `pull_request:`. This conserves the shared 71-repo CI minutes budget.

```yaml
on:
  push:
    branches: [main]
    paths:
      - '.github/workflows/**'
      - 'Makefile'
      - 'lefthook.yml'
  pull_request:
    paths:
      - '.github/workflows/**'
      - 'Makefile'
      - 'lefthook.yml'
```

Workflows that must always run (release, scheduled drift, scorecards, etc.) keep no
path filter. **`merge_group:` cannot carry a `paths`/`paths-ignore` filter at all** —
GitHub Actions only supports path filtering on `push`, `pull_request`, and
`pull_request_target` (`actionlint` rejects it on `merge_group`, confirmed against
`ffreis-project-templates` PR #64). A workflow with a `merge_group:` trigger runs
unconditionally on merge-queue checks regardless of what changed.

### Reusable workflows (devops/ffreis-workflows-*)

The same standards apply to reusable workflows defined in the `devops/` repos:

- Per-job `timeout-minutes` and `permissions:` are still required (defense-in-depth —
  callers shouldn't need to over-grant just because a reusable workflow under-declares).
- Reusable workflow definitions use `on: workflow_call:` so path filters don't apply,
  but the self-test/CI workflows that live alongside them do follow all the rules above.
- **Each carries the draft gate** so the whole fleet inherits it from one place: a
  `run_on_draft` boolean input (default `false`) plus, on the root job,
  `if: ${{ inputs.run_on_draft || vars.CI_RUN_ON_DRAFT == 'true' || github.event_name != 'pull_request' || github.event.pull_request.draft == false }}`.
  Callers then get "no CI on draft" with no per-job `if:`; pass `run_on_draft: true` to opt
  a cheap job (e.g. fmt) back into running on drafts.

### CI cost control

The fleet shares a finite monthly Actions-minutes budget across 80+ repos. The goal is
**not less CI** — it is full CI *at the gates that matter* (promotion to ready, push to a
default branch) and *~zero CI on work-in-progress*. Beyond the structural rules above,
every workflow respects these spend levers:

| Lever | Rule | Why |
|---|---|---|
| **Draft gating** | PR jobs skip on draft (per-job `if:` guard, or call a fleet reusable that carries the gate); `on.pull_request.types` lists `ready_for_review` so promotion fires CI | A Claude/agent-driven PR is pushed many times while still a draft — full CI on each push burns the budget. |
| **Bounded `push:`** | Every `push:` trigger sets `branches:` (normally `[main]`, or `[main, develop]`) | An unbounded `on: push` runs full CI on *every* feature-branch push, double-billing what the draft PR already gates. **Fleet target + current state: zero unbounded `push:` triggers.** |
| **Scanner tiering** | Heavy scanners (CodeQL, semgrep, scorecards, snyk, lighthouse, a11y, SEO, mutation, fuzz) run on `schedule:` and/or push-to-default — **never** on every draft PR | These are the priciest jobs; a nightly/weekly cadence on the merged tree gives the coverage without per-WIP cost. |
| **Required-check safety** | A required status check must always *run and report* — never `skip`. A check that is sometimes irrelevant (e.g. a promote-gate on a CI-only PR) must still run and **pass** (detect "nothing to do" → exit 0), not be skipped | A skipped required check reads as "unsatisfied" and wedges merge; the wrong fix is then weakening branch protection. Run-and-pass keeps protection intact. See `general-promote-gate.yml`'s CI-only-change short-circuit. |
| **Cron jitter** | New scheduled workflows pick a per-repo/per-workflow minute+hour, not a shared round value | Many repos currently share `0 6 * * 1` (security) / `0 3 * * 0` (automation). GitHub **queues** simultaneous crons — so this is queue latency, *not* extra minutes — but jittering (`<repo-hash % 60> <6..9> * * 1`) smooths the herd. Low priority precisely because it does not change billing. |

**Self-enforcing, no drift:** the draft-gating + `ready_for_review` + concurrency rules are
asserted on every PR by `general-workflows-policy.yml`; the local mirror is
`quality-kit/scripts/ci_draft_policy.py` (`make -C quality-kit ci-standards`). New repos
inherit the gated, structured workflows from the Copier templates
(`platform/ffreis-project-templates`) — **fix the template, not 80 copies** — so the standard
cannot be missed on a newly-scaffolded repo.

**Proactive backstops against a sudden burst** (two layers, set both):
1. **Hard ceiling** — the GitHub billing **spending limit** (Settings → Billing → Spending
   limit). A runaway loop physically cannot exceed it. This is the only true cap; set it.
2. **Early warning** — the `ffreis-platform-monitor-lambda` Actions-burst alert emails when
   fleet-wide workflow-run volume spikes past a tunable threshold in a short window
   (`ACTIONS_BURST_THRESHOLD` / `ACTIONS_BURST_WINDOW_MIN`), so a spike is caught long before
   it reaches the ceiling.

---
