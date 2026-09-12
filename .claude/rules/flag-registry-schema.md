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

`quality-kit/scripts/audit-repo-standards.sh`'s `FLAG-SEAMS` NICE gap class flags any
repo with boundary-crossing code (env-branches, mock/real swaps) but no
`flags/flags.json` — presence-only heuristic, not schema validation. The
`flag-seam-auditor` subagent (`.claude/agents/flag-seam-auditor.md`) does the deeper,
semantic audit.
