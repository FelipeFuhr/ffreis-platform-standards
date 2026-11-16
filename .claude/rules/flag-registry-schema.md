---
paths:
  - "flags/**"
  - "scripts/validate-flag-registry*"
---

# Flag registry schema

`flags/flag-registry.schema.json` is the canonical schema behind the "every point of
variation is a declared flag" philosophy (`.claude/workspace/AGENTS.md` §
"Every point of variation is a declared flag"). Any repo that owns a dev toolbar and/or
runtime feature flags declares them in `flags/flags.json`, which `$schema`-references
this file:

```json
{
  "$schema": "https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards/main/flags/flag-registry.schema.json",
  "version": 1,
  "project": "<repo-name>",
  "flags": []
}
```

Each entry is tagged on four axes — `kind` (adapter/service/value/gate), `category`
(toolbar grouping: data/api/model/content/lang/feature/infra, plus `quality`), `binding`
(compile/runtime), `effect` (route/toggle) — plus a `default` and a `seam` (the one code
location that reads the flag). `category: model` flags MUST default to the mock/cheapest
option (cost guard — never bill a paid backend from an unconfigured toolbar). Full field
reference is in the schema's own `description`/`$defs` — it's self-documenting.

## `category: quality` — the same mechanism, applied to component/media rules

`quality` extends the registry from *infrastructure* variation (which adapter, which
downstream, which value, which feature) to **component and media quality rules**:
images, fonts and text, document structure, accessibility. The principle is the
existing one restated — maximum rigor is the default, and every opt-out is a declared,
reasoned entry rather than a silent gap. These entries never appear in a dev toolbar;
they are build-time gates.

A quality entry adds three fields:

| Field | Meaning |
|---|---|
| `rule` | an id from the controlled vocabulary in `flags/quality-rules.md`; an id not listed there is rejected, so a typo cannot pose as a declared rule |
| `output_target` | `browser-live` / `document-export` / `raster-export` — which class of output the rule can even apply to. Lazy-loading is meaningless for a batch-rendered image: there is no "later" to defer to |
| `exceptions` | `{scope, reason, added}` rows carrying the justified carve-outs |

The conformance rule that stops this becoming documentation-ware: **an entry claiming
enforcement must name the gate enforcing it in `seam`; an entry that does not enforce
must carry a reasoned `exceptions` row.** Both directions are checked, so neither a
vacuous declaration nor a quietly-disabled rule validates. Do not put a status string
such as `"NONE YET"` in `seam` — `seam` names a real code location or stays absent, and
unenforced debt is expressed as `default: "off"` plus the reason.

## Validating a registry

```bash
make validate-flags                                          # this repo
python3 scripts/validate-flag-registry.py flags/flags.json    # from a consumer repo
```

`scripts/validate-flag-registry.py` is deliberately dependency-free (no `jsonschema`)
so a consumer repo can vendor it next to the schema and the vocabulary. It checks
structure *and* the semantic conformance JSON Schema cannot express: the quality rules
above, placeholder exception reasons, duplicate flag names, and the `category: model`
cost guard — which was documented here for a long time with nothing enforcing it.

Every enum, required-key list and rule id is **extracted from the schema and the
vocabulary at runtime** rather than copied into the validator. A copy is how a
validator and the artifact it validates drift apart while both still pass; if an
extraction ever fails, the validator exits 2 rather than silently treating every value
as valid.

`scripts/validate-flag-registry-selftest.sh` (run by `make test` and by CI) is the
behaviour lock: a fully valid registry must pass, and each violation class must be
rejected *for the expected reason*, so a fixture cannot pass because of an unrelated
typo. Neutering the validator flips 20 of its cases to failure — that anti-vacuity
property is the point of the suite.

`quality-kit/scripts/audit-repo-standards.sh`'s `FLAG-SEAMS` NICE gap class flags any
repo with boundary-crossing code (env-branches, mock/real swaps) but no
`flags/flags.json` — presence-only heuristic, not schema validation. The
`flag-seam-auditor` subagent (`.claude/agents/flag-seam-auditor.md`) does the deeper,
semantic audit.

## `effect: constant` — a magic literal given a name

`route` demands at least two options and `toggle` is on/off, so neither fit a
value that has exactly one legitimate setting and exists purely so the literal
lives in one named place instead of three. That gap was not theoretical: the
fleet's one such flag (`heavy-heater`'s `support_fee_rate`, extracted from a
hardcoded `(subtotal * 0.08).clamp(…)`) had been declared `effect: route` with a
single-item `options` list, and had therefore been FAILING this validator since
the day it was written — unnoticed, because nothing in any consumer repo ran it.

A constant:

```json
{
  "name": "support_fee_rate",
  "kind": "value", "category": "feature", "binding": "compile",
  "effect": "constant", "value_type": "number", "default": 0.08,
  "seam": "launcher order support-fee calc",
  "description": "Support fee rate, declared once so the literal is not repeated."
}
```

- carries **no `options`** — if it has alternatives it is a `route`, and a
  one-item `options` list is the signature of a constant forced into the route
  shape. The validator says exactly that, and points at this effect.
- requires `value_type` and `default`. The default *is* the value; a constant
  with no value declares nothing.

### A diagnostic worth keeping

`default 0.08 is not one of its options ['0.08']` reads as a bug in the
validator, not in the registry — and that is the literal message the fleet's
failing registry produced. `options` holds strings, so a numeric default can
match only as text. The validator now names the type and offers both fixes
(quote the default, or make it a typed constant) rather than stating an
apparent contradiction.

## Wiring the gate in a consumer: one line

`scripts/gate-registries.sh` validates whichever registries a repo owns —
`flags/flags.json`, `metrics/metrics.json`, or both — against the schemas at a
pinned commit of this repo. A consumer wires it once:

```make
# ffreis-platform-standards, pinned. A tag or branch is NOT a pin: the gate's
# verdict would move under the repo without its diff changing, and the script
# rejects anything that is not a 40-char sha for exactly that reason.
STANDARDS_SHA ?= <40-char sha>

validate-registries:
	@bash .bin/standards/gate-registries.sh "$(STANDARDS_SHA)"
```

The first two metric-registry consumers each grew their own four-variable,
cached-download Makefile target instead. Wiring the flag gate into three more
repos would have made five copies of the same twelve lines — already diverging,
since the flag validator needs three files where the metric one needs two. The
next registry kind extends this one script rather than every Makefile in the
fleet.

Two properties worth not losing:

- **A repo with no registry exits 0**, with a line saying what it did not find.
  A gate that cannot be wired unconditionally gets wired selectively, and then
  the repo that most needs it is the one nobody remembers to wire. Whether a
  repo *should* own a registry is `audit-repo-standards.sh`'s question
  (`flag-seams` / `metric-seams`), not this script's.
- **An unfetchable tool is exit 2, never a pass.** If a stale pin reported
  success, every consumer would silently gate against nothing the moment a file
  moved in this repo. A fetched HTML error page is caught too — those arrive as
  200 OK and non-empty, and would otherwise fail later as a syntax error, which
  reads as a broken registry rather than a broken pin.

Once warmed the cache needs no network, so the gate runs in a sandboxed CI job.

