---
paths:
  - "flags/**"
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
(toolbar grouping: data/api/model/content/lang/feature/infra), `binding`
(compile/runtime), `effect` (route/toggle) — plus a `default` and a `seam` (the one code
location that reads the flag). `category: model` flags MUST default to the mock/cheapest
option (cost guard — never bill a paid backend from an unconfigured toolbar). Full field
reference is in the schema's own `description`/`$defs` — it's self-documenting.

Reference implementation: `heavy-heater/flags/flags.json` (6 flags, all four `kind`
values represented) + `heavy-heater/launcher/src/flags.rs` (registry parse/resolve, dev
toolbar rendered generically from the registry instead of hand-coded per feature).

## `flags/flagsgen.py` — the canonical projector

The toolbar, the runtime resolver and the build config are *projections* of the
registry. `flags/flagsgen.py` is the fleet's one generator for them, and lives here so
no consumer repo forks a private copy:

```bash
flagsgen.py validate --registry flags/flags.json --schema flags/flag-registry.schema.json
flagsgen.py emit-js  --registry flags/flags.json --out src/assets/js/flags.js
flagsgen.py emit-env --registry flags/flags.json --out flags/flags.env
flagsgen.py check    --registry flags/flags.json --generated src/assets/js/flags.js
```

Three things about it are deliberate and must not be "simplified":

- **`validate` hard-fails without `jsonschema`.** There is no built-in fallback engine,
  because a hand-rolled structural check is always laxer than Draft 2020-12 and a laxer
  stub does not miss bugs, it *certifies* them.
- **Drift is gated by a checksum, not by re-running the generator.** Every emitted file
  carries `registry-sha256:` in its header; `check` compares it to the live registry.
  A consumer's CI proves its projections are current with nothing but the standard
  library, and no test ever reimplements generation (that would be a second generator).
- **The emitted JavaScript resolves flags at script-parse time, never inside a
  `DOMContentLoaded` listener.** Sibling scripts read flag values during their own boot;
  a listener registered by the flag script fires in registration order, so an override
  applied there lands after those reads and silently has no effect. Only DOM mounting is
  deferred. The generated file carries this as a banner comment — keep it.

An `env` field on a flag names the environment variable it is read from (default: the
flag's `name` uppercased). Declare it explicitly whenever the deployed service already
reads a prefixed name, so the generated resolver and the service cannot disagree.

`quality-kit/scripts/audit-repo-standards.sh`'s `FLAG-SEAMS` NICE gap class flags any
repo with boundary-crossing code (env-branches, mock/real swaps) but no
`flags/flags.json` — presence-only heuristic, not schema validation. The
`flag-seam-auditor` subagent (`.claude/agents/flag-seam-auditor.md`) does the deeper,
semantic audit.
