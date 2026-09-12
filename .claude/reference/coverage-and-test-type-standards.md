## Coverage and test-type standards

Fleet-wide minimums — **both unit and integration coverage are gated separately, each at
the same floor** (enforced via `make coverage-gate` and `make integration-coverage-gate`
in the `complex` lefthook tier):

| Language | Min unit coverage | Min integration coverage | Tool | Integration test convention | Property tests | Mutation threshold |
|---|---|---|---|---|---|---|
| Go | 75% | 75% | `go test -coverprofile` + `check_coverage_gate.sh` | `//go:build integration` test files, own `-coverprofile` run for `integration-coverage-gate` | optional | 60% (gremlins) |
| Rust | 75% | 75% | cargo-llvm-cov (line coverage) | `tests/` per crate for service ports, own `cargo llvm-cov` invocation for `integration-coverage-gate` | proptest recommended | 60% (cargo-mutants) |
| Python | 75% (branch) | 75% (branch) | pytest-cov (`fail_under`) | separate `tests/integration_tests/`, own `--cov-fail-under` invocation for `integration-coverage-gate` | hypothesis recommended | 60% (mutmut) |

New repos must set `coverage-gate` and `integration-coverage-gate` Makefile targets that
each enforce at least the floor above; a repo with no integration-test surface at all
(pure library, no service boundary) may define `integration-coverage-gate` as a no-op
that says so explicitly — it must still exist, since #62 (see "Simple vs
complex/release tiers" above) a *missing* target fails the tier exactly like a failing
one. A repo already enforcing a stricter floor (e.g. 90%) keeps its stricter number;
never lower an existing floor to match this one.

### Mutation testing: PR-time vs scheduled

The "mutation threshold" column above is a *mutant-kill-rate* target, unrelated to the
unit/integration coverage floors — do not conflate the two metrics. It is enforced in two
places that run **different mutant sets against the same formula**:

| | target | scope | where it runs | wall-clock |
|---|---|---|---|---|
| **PR-time gate** | `make mutation-diff` | only the lines this branch changed (`cargo mutants --in-diff`) | `release` lefthook tier → `/ready` | minutes |
| **Full sweep** | `make mutation` | the whole crate | scheduled `rust-mutation.yml` cron + on demand | tens of minutes to hours |

Both call the same `scripts/mutation_score.sh`, so the two gates can never disagree about
what "passing" means. Both are REQUIRED targets: a missing one **fails** the tier rather
than skipping, so implement them in the same PR that adopts or bumps the config pin.

> **Rollout status (2026-09-06).** The table's right-hand column is the target state, not
> yet the fleet's state. Surveyed today, the consumer repos wire `rust-mutation.yml` on
> `pull_request` rather than on a cron, and most still pin it at `v1.3.0` — the release
> whose scorer read the wrong path and reported a clean 100% without measuring anything
> (fixed upstream in v2.0.1). Moving the whole-crate sweep onto a schedule and off the PR
> trigger, and bumping those pins, is the CI-side half of this change and is tracked
> separately from the local `release`-tier fix that lands here. A working pattern for it
> already exists — a standalone `mutation.yml` on `cron: "0 2 * * 0"` + `workflow_dispatch`
> — carried by open PRs on `ffreis-token-vault` (#11), `ffreis-shamir` (#13) and
> `ml/ffreis-btc-features` (#12), unmerged since 2026-08-08. Copy that, do not reinvent it.

**Why the PR gate is diff-scoped.** The `release` tier fires on every branch whose
conventional commits imply a minor/major bump — that is every `feat:` branch. An unscoped
whole-crate sweep does not fit in a promotion gate: `ffreis-urbs-admin` is ~1,600 mutants
at ~44s each, ~19 hours against a ~50 minute budget. It was killed every time, so no
`feat:` PR on that repo could be promoted at all. Nothing about that is specific to one
branch — it is a function of crate size, and every Rust repo reaches it as it grows.

Measured on that repo's PR #18 branch, 2026-09-06:

| | mutants | wall-clock | result |
|---|---|---|---|
| `make mutation` (whole crate) | **1,605** | ~19h projected | never completed |
| `make mutation-diff` (this branch) | **91** | **41 min** | 46 caught / 12 missed / 17 timeout / 16 unviable → **79%**, passes the 70% floor |

The 41 minutes were on a box under heavy concurrent load (load average ~26, several
sibling sessions building); the 17 timeouts are an artefact of that same contention
against `--minimum-test-timeout 60` and are excluded from the score, since no test could
have caught them. Expect materially less on an idle machine. The run also surfaced 12
genuinely untested mutations in the branch's own new code — which is the point: the same
crate's whole-crate score would have been dominated by the ~1,500 mutants this PR never
touched.

Diff-scoping is also the better *measure*, not merely the cheaper one. A whole-crate score
is dominated by code the PR never touched, which is exactly how a mutation gate reports a
reassuring number while saying nothing about the change under review. `--in-diff` asks the
question a PR gate should ask: *are these new lines tested?*

**Two traps, both encoded in `scripts/mutation-diff.sh` rather than left to the caller:**

1. **cargo-mutants ignores `CARGO_TARGET_DIR` for its per-mutant scratch copies** — it
   copies the source tree under `$TMPDIR`. Left at the default that is `/tmp` on the root
   filesystem, where abandoned runs have filled the disk to zero and crashed sessions. Set
   `TMPDIR` deliberately and remove it afterwards. It must **never** point inside the
   repo: cargo-mutants copies the working tree wholesale, so a scratch dir inside it copies
   its own previous copy, recursively, until the path exceeds the OS limit. The script
   hard-fails on that instead of only documenting it.
2. **A shared target dir corrupts results.** cargo-mutants passes its environment down to
   every mutant build, so an inherited `CARGO_TARGET_DIR` puts the mutants and the real
   working tree in the same bucket — after which the next `cargo test` in that tree can
   report a *specific, plausible-looking wrong assertion* sourced from a mutated build.
   That is worse than a broken build, because it is indistinguishable from a real
   regression. The script unsets it, and also redirects `CACHE_TIER` into its own scratch
   so this workspace's `~/.cargo/bin/cargo` shim cannot re-derive one behind its back.

**Go and Python are NOT yet diff-scoped** — `lefthook/go.yml` and `lefthook/python.yml`
still call the whole-suite `make mutation` in their `release` tiers. The defect class is
the same, but neither gremlins nor mutmut has a line-level `--in-diff`; the equivalent fix
is coarser (scope gremlins to the packages holding changed files, mutmut to the changed
paths) and no repo has yet been measured blowing the budget, so it is recorded here as
open rather than shipped untested.
