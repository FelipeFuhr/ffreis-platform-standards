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
