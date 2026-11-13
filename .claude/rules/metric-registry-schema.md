---
paths:
  - "metrics/**"
  - "scripts/validate-metric-registry*"
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
