---
paths:
  - "metrics/**"
  - "scripts/validate-metric-registry*"
  - "scripts/metric-coverage-report*"
---

# Metric registry schema

`metrics/metric-registry.schema.json` is the canonical schema behind the "every
published number is a declared metric" philosophy
(`.claude/workspace/reference/every-published-number-is-a-declared-metric.md`).
Any repo that publishes numbers — a report, a dashboard, a rollup, a scheduled
email — declares them in `metrics/metrics.json`, which `$schema`-references this
file:

```json
{
  "$schema": "https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards/main/metrics/metric-registry.schema.json",
  "version": 1,
  "project": "<repo-name>",
  "metrics": []
}
```

Each entry is tagged on five axes — `population` (whose behaviour it describes),
`source` (the signal feeding it), `denominator` (what a quotient is taken over),
`min_sample` (the size below which it is withheld), and `coverage` (the scenarios
that prove it still works) — plus a `seam`, the one code location that computes
it. Full field reference lives in the schema's own `description`/`$defs`; it is
self-documenting.

## Why these axes and not others

Each one names a way a published number has actually misled a reader, not a
category someone liked the shape of:

| Axis | The failure it prevents |
| --- | --- |
| `population` | a consent-gated sample read as the whole traffic |
| `source` | a report section with no feeding signal, rendering as a zero |
| `denominator` | a count presented where a share was meant |
| `min_sample` | a median or p90 computed over one observation |
| `coverage` | a section no scenario exercises, so nothing notices it break |

## The rule that carries the most weight

**A metric whose `population` is `consenting-visitor` must name a `baseline`
whose population is `all-traffic`.** Telemetry that only fires after a visitor
accepts it cannot measure the visitors who refused, so it can never be its own
denominator. Without a baseline, "3 sessions" is read as the traffic rather than
as 3 of some unknown larger number. The baseline has to be measured a different
way — server logs, edge metrics — because a baseline collected through the same
gate carries the same blind spot, and the validator rejects one that does.

## Enforcement

`scripts/validate-metric-registry.py` checks what JSON Schema cannot: that
`denominator` and `baseline` resolve to declared metrics, that a baseline is
genuinely `all-traffic`, that a metric is either covered or carries a reasoned
exception, that a `mixed` population says what it mixes, and that an exception
reason is a real reason rather than `TODO`.

Run it with `make validate-metrics`; it is part of `make fmt-check`, and its
behaviour lock (`scripts/validate-metric-registry-selftest.sh`) runs in
`make test` and in CI. The validator is deliberately dependency-free so a
consumer repo can vendor it alongside the schema and gate its own registry.

Both directions matter. A validator that only ever accepts passes any suite
built from valid fixtures, so every negative case in the selftest asserts the
specific message — a fixture cannot pass for the wrong reason.

## Ship the gate with the field

Do not add a field here before something enforces it. The sibling flag registry
is the cautionary case: it has a complete validator, and consumer registries
still fail it today because nothing runs it on them. A declared axis nobody
checks is documentation, not a standard.

## Two tools, two different questions

`scripts/validate-metric-registry.py` answers **"is this registry well formed
and internally consistent"** — required keys, enum membership, references that
resolve, a consent-gated metric naming an all-traffic baseline. It is a gate:
`make validate-metrics`, and a consumer wires it into its own `fmt-check`/CI.

`scripts/metric-coverage-report.py` answers the question a reader of the report
actually has: **"which of these numbers is still being produced by
something?"** A registry passes the validator with every metric carrying a
reasoned exception — that is legal, and it is also a project where nothing
proves any published number works. So the reporter's normal output is a shape,
not a verdict:

```
ffreis-uxstoryteller  (metrics/metrics.json)
  coverage   [###########.............] 18/39 metrics  (46.2%)
  exception  21 metric(s) carried by a reasoned exception — declared, not proven
  scenarios, by how many metrics depend on them:
    traffic-deep-read                16
    multi-page-journey                4
```

That blast-radius column is the reason it exists in this form. Sixteen of
eighteen covered metrics resting on one scenario is invisible from either side
alone: the registry sees eighteen proofs, the corpus sees one file.

### The one thing it fails on

A `coverage` id that matches no scenario. A rename or deletion in the corpus
silently un-covers every metric that named it — the registry keeps asserting
coverage, the validator keeps passing, and nothing runs. That is the metric
registry's version of the gap this whole standard was written to close, one
level up, so it exits 1 and names the metrics that lost their proof.

Pass `--scenarios <dir>` for that check; the ids are the filenames, with a
trailing `.spec` stripped. Without it the reporter only describes, and cannot
fail.

An **empty** corpus directory is exit 2, not "everything is dangling": a
tooling failure must not masquerade as a hundred findings. Same for an
unreadable registry, and for a registry that is a JSON array rather than an
object.

### Reading the report

- **`VACUOUS`** — a metric with neither coverage nor a reasoned exception. The
  validator rejects these, so seeing one means the registry is not gated.
- **exceptions older than 180 days** are surfaced, not failed. The reason was
  written about a situation that may no longer hold.
- **"scenarios no metric names"** is usually a missing registry entry, not
  dead corpus. A scenario that exercises a signal nothing declares is a
  published number waiting to be found.
- **`n/a` rather than `0%`** for an empty registry: a share of nothing is not
  zero percent covered, and `0%` reads as a finding.

