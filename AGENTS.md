# ffreis-platform-standards

Shared configuration standards for all repos in the ffreis fleet. Every repo extends from
here instead of copy-pasting configs.

## Where the rest lives

Every other `##` section this file used to carry was moved **mechanically and
verbatim** into `.claude/rules/` (auto-loaded when a touched file matches its
`paths:` glob — zero cost otherwise) or `.claude/reference/` (read on demand,
by name — zero cost at session start). Nothing below was rewritten or
summarized in the move; `.claude/reference/_manifest.json` records the exact
heading → file → byte-count mapping, and `scripts/check-instructions.sh`
(`make lint-instructions`) fails if a mapped file ever goes missing or empty.

**Path-scoped rules** (auto-load the instant you touch a matching path):

| Heading | Rule file | Loads on |
| --- | --- | --- |
| Flag registry schema | `.claude/rules/flag-registry-schema.md` | `flags/**` |
| Renovate presets | `.claude/rules/renovate-presets.md` | `renovate/**`, `renovate.json` |
| Lefthook remotes | `.claude/rules/lefthook-remotes.md` | `lefthook/**`, `lefthook.yml` |
| golangci standard | `.claude/rules/golangci-standard.md` | `golangci/**` |
| Local CI runner (`scripts/`) | `.claude/rules/local-ci-runner-scripts.md` | `scripts/install_act.sh`, `scripts/run-ci-local.sh`, `scripts/ci-local.env.example` |
| GitHub Actions CI standards | `.claude/rules/github-actions-ci-standards.md` | `.github/workflows/**` |

**On-demand reference** (read by name when the task needs it):

| Heading | Reference file |
| --- | --- |
| What lives here | `.claude/reference/what-lives-here.md` |
| Coverage and test-type standards | `.claude/reference/coverage-and-test-type-standards.md` |
| Async event flows — convention | `.claude/reference/async-event-flows-convention.md` |
| CI and versioning | `.claude/reference/ci-and-versioning.md` |
| Workspace docs (`workspace/`) | `.claude/reference/workspace-docs-workspace.md` |
| Making fleet-wide changes | `.claude/reference/making-fleet-wide-changes.md` |
| Workspace Essentials | `.claude/reference/workspace-essentials.md` |
| Public repo hygiene policy | `.claude/reference/public-repo-hygiene-policy.md` |

**`workspace/` vs `.claude/reference/`.** This repo's own "Workspace docs" section
(above) once described `workspace/AGENTS.md`/`workspace/CLAUDE.md` as tracked here;
the later "Public repo hygiene policy" section superseded that after a 2026-05-29
audit and `workspace/` is now gitignored (this repo is publicly visible, and those
files carry private repo names). New reference files therefore live under
`.claude/reference/`, matching every other repo in this split batch, not under the
gitignored `workspace/`.

**Rollback**, same shape as the hub precedent this mirrors (commit `288f0e3` in
`.claude`) and the fleet repos it was already applied to (`ffreis-job-arbiter`#110,
`ffreis-deck-actions`#89, `ffreis-pw2pw`#83, `ffreis-home-infra`#174): the split is
verbatim and the manifest is ordered, so reverting this commit (or restoring
`AGENTS.md` from the commit before it and deleting `.claude/rules/`,
`.claude/reference/`) reconstructs the original file exactly.
