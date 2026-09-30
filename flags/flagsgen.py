#!/usr/bin/env python3
"""flagsgen — project the fleet flag registry into its consumers.

`flags/flags.json` is the ONE declaration of every deliberate point of
variation in a project (see `flags/flag-registry.schema.json` and
`.claude/rules/flag-registry-schema.md`).  Everything downstream of it — the
dev toolbar, the runtime resolver, the build/deploy config — is a *projection*
of that file, never a hand-maintained per-feature switch.  If a consumer has to
be edited each time a flag is added, the design has failed.

This script is the fleet's canonical projector.  It lives here, next to the
schema it reads, so no consumer repo forks a private copy of it.

    flagsgen.py validate --registry flags/flags.json \
                         --schema   flags/flag-registry.schema.json
    flagsgen.py emit-js  --registry flags/flags.json --out src/assets/js/flags.js
    flagsgen.py emit-env --registry flags/flags.json --out flags/flags.env
    flagsgen.py check    --registry flags/flags.json --generated src/assets/js/flags.js

Two deliberate design decisions
-------------------------------

1. **`validate` refuses to run without `jsonschema`.**  A hand-rolled
   "structural check" is always laxer than the real Draft 2020-12 validator,
   and a laxer stub does not merely miss bugs — it *certifies* them.  There is
   no built-in fallback engine on purpose.  Install `jsonschema` (it is pure
   Python, no build step) or do not claim the registry was validated.

2. **Drift is gated by a checksum, not by re-running the generator.**  Every
   emitted file records `registry-sha256:` in its header.  `check` compares
   that against the live registry.  A consumer's CI therefore needs nothing but
   the Python standard library to prove its committed projections are current —
   it never needs this script, and nothing ever reimplements generation in a
   test (which would be a second generator, i.e. the bug this file exists to
   prevent).

Env-var names
-------------

Each flag's environment variable is its optional `env` field, else its `name`
uppercased.  The `env` field exists so a registry can describe a variable that
already ships under a prefixed name without renaming the flag.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

VERSION = "1.0.0"

GENERATOR_ID = "ffreis-platform-standards/flags/flagsgen.py"

# Hosts a dev toolbar is allowed to exist on.  Anything else is treated as
# production: the toolbar is not mounted AND stored overrides are ignored, so a
# stale localStorage entry can never re-route a real user's traffic.
DEFAULT_DEV_HOSTS = [
    "localhost",
    "127.0.0.1",
    "::1",
    "*.local",
    "*.ffreis.com",
    "*.cloudfront.net",
]


# --------------------------------------------------------------------------
# registry helpers
# --------------------------------------------------------------------------


def load_registry(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"flagsgen: registry not found: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"flagsgen: registry is not valid JSON: {path}: {exc}")


def registry_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def env_name(flag: dict) -> str:
    return flag.get("env") or flag["name"].upper()


def default_as_str(flag: dict) -> str:
    value = flag.get("default")
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def header(kind: str, registry_path: Path, sha: str, project: str) -> list[str]:
    """The provenance block every emitted file carries.

    `registry-sha256` is the drift gate: `flagsgen.py check` re-hashes the
    registry and compares.  Keep the key spelling stable — consumers grep it.
    """
    return [
        f"GENERATED FILE — DO NOT EDIT BY HAND ({kind}).",
        f"generator:       {GENERATOR_ID} v{VERSION}",
        f"source-registry: {registry_path.as_posix()}",
        f"project:         {project}",
        f"registry-sha256: {sha}",
        "regenerate:      make flags     (drift gate: make flags-check)",
        "",
        "Add a flag by declaring it in the registry and re-running the",
        "generator. Editing this file by hand desynchronises it from the one",
        "declaration every other consumer reads.",
    ]


# --------------------------------------------------------------------------
# validate
# --------------------------------------------------------------------------


def cmd_validate(args: argparse.Namespace) -> int:
    registry_path = Path(args.registry)
    schema_path = Path(args.schema)
    registry = load_registry(registry_path)
    schema = json.loads(schema_path.read_text(encoding="utf-8"))

    try:
        import jsonschema
    except ImportError:
        raise SystemExit(
            "flagsgen: jsonschema is not installed, and there is deliberately no\n"
            "          built-in fallback: a laxer stub validator certifies the bugs\n"
            "          the real one would have caught.\n"
            "          Install it with:  python3 -m pip install jsonschema"
        )

    try:
        from importlib.metadata import version as _dist_version

        engine_version = _dist_version("jsonschema")
    except Exception:  # pragma: no cover - metadata is advisory only
        engine_version = "unknown"

    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    validator = validator_cls(schema)
    errors = sorted(validator.iter_errors(registry), key=lambda e: list(e.absolute_path))

    print(f"flagsgen validate v{VERSION}")
    print(f"  registry: {registry_path}")
    print(f"  schema:   {schema_path} ({schema.get('$id', 'no $id')})")
    print(f"  engine:   jsonschema {engine_version} / {validator_cls.__name__}")

    if errors:
        for err in errors:
            where = "/".join(str(p) for p in err.absolute_path) or "<root>"
            print(f"  FAIL {where}: {err.message}")
        print(f"INVALID — {len(errors)} schema violation(s).")
        return 1

    # Beyond the schema: the fleet cost guard.  The schema can say a default
    # exists; only this check can say it is the cheap one.  An `adapter` routes
    # between implementations and its options are ordered least-real -> most-real,
    # so the guarded default is always options[0].
    guard_failures = []
    for flag in registry.get("flags", []):
        if flag.get("kind") != "adapter" or flag.get("effect") != "route":
            continue
        options = flag.get("options") or []
        if options and flag.get("default") != options[0]:
            guard_failures.append(
                f"{flag['name']}: default {flag.get('default')!r} is not the cheapest "
                f"option {options[0]!r} (options are ordered least-real -> most-real)"
            )

    for flag in registry.get("flags", []):
        env = env_name(flag)
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", env):
            guard_failures.append(f"{flag['name']}: env var {env!r} is not SCREAMING_SNAKE_CASE")

    seen_env: dict[str, str] = {}
    for flag in registry.get("flags", []):
        env = env_name(flag)
        if env in seen_env:
            guard_failures.append(
                f"{flag['name']}: env var {env} already claimed by {seen_env[env]}"
            )
        seen_env[env] = flag["name"]

    for line in guard_failures:
        print(f"  FAIL cost-guard/{line}")
    if guard_failures:
        print(f"INVALID — {len(guard_failures)} cost-guard violation(s).")
        return 1

    adapters = [f for f in registry.get("flags", []) if f.get("kind") == "adapter"]
    print(f"  cost guard: {len(adapters)} adapter flag(s), every default is the cheapest option")
    print(f"VALID — {len(registry.get('flags', []))} flag(s) in {registry.get('project', '?')}.")
    return 0


# --------------------------------------------------------------------------
# emit-js — the dev toolbar + browser-side resolver
# --------------------------------------------------------------------------

# `toolbar.template.js` is STATIC: it iterates the registry rather than naming
# any flag.  Only the header, the inlined registry and the dev-host list vary
# per project.  That is what makes the toolbar a projection and not a
# hand-written panel — a new flag appears in it with no edit to any JavaScript.
#
# It is a real .js file, not a Python string, so `node --check` and any JS
# linter can see it.  (It also keeps this file recognisable as Python: with the
# template inlined, `file --mime-type` reports flagsgen.py as JavaScript and the
# fleet's staged-binary-file hygiene hook rejects the commit.)
JS_TEMPLATE = Path(__file__).resolve().parent / "toolbar.template.js"


def cmd_emit_js(args: argparse.Namespace) -> int:
    registry_path = Path(args.registry)
    registry = load_registry(registry_path)
    sha = registry_sha256(registry_path)

    # The registry is inlined so resolution needs no fetch. An async fetch
    # would push resolution past every other script's boot — the same failure
    # the SYNCHRONOUS BOOT banner describes.
    inlined = json.loads(json.dumps(registry))
    inlined.pop("$schema", None)
    for flag in inlined.get("flags", []):
        flag["env"] = env_name(flag)
        flag.setdefault("scope", "session")

    dev_hosts = args.dev_host or DEFAULT_DEV_HOSTS

    lines = ["/*"]
    for line in header("browser resolver + dev toolbar", registry_path, sha, registry.get("project", "?")):
        lines.append((" * " + line).rstrip())
    lines.append(" */")
    lines.append("var REGISTRY = " + json.dumps(inlined, indent=2, sort_keys=False) + ";")
    lines.append("var DEV_HOSTS = " + json.dumps(dev_hosts) + ";")
    lines.append(JS_TEMPLATE.read_text(encoding="utf-8").strip())
    lines.append("")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"flagsgen: wrote {out} ({len(inlined.get('flags', []))} flags, registry {sha[:12]})")
    return 0


# --------------------------------------------------------------------------
# emit-env — the build/deploy config projection
# --------------------------------------------------------------------------


def cmd_emit_env(args: argparse.Namespace) -> int:
    registry_path = Path(args.registry)
    registry = load_registry(registry_path)
    sha = registry_sha256(registry_path)

    lines = []
    for line in header("build/deploy config", registry_path, sha, registry.get("project", "?")):
        lines.append(("# " + line).rstrip())
    lines.append("#")
    lines.append("# Every variable below is the flag's DECLARED DEFAULT — the cost- and")
    lines.append("# safety-guarded value. Terraform, compose files and .env templates take")
    lines.append("# these as their baseline; a deployment overrides one by naming it, never")
    lines.append("# by editing this file.")
    lines.append("")
    for flag in registry.get("flags", []):
        lines.append(f"# {flag['kind']}/{flag['category']} · {flag['binding']} · {flag['effect']}")
        if flag.get("options"):
            lines.append("# options (least-real -> most-real): " + ", ".join(flag["options"]))
        if flag.get("cost_guard"):
            lines.append("# COST GUARD: moving off the default can bill real inference/storage.")
        if flag.get("seam"):
            lines.append(f"# seam: {flag['seam']}")
        lines.append(f"{env_name(flag)}={default_as_str(flag)}")
        lines.append("")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"flagsgen: wrote {out} ({len(registry.get('flags', []))} vars, registry {sha[:12]})")
    return 0


# --------------------------------------------------------------------------
# check — the stdlib-only drift gate
# --------------------------------------------------------------------------

SHA_RE = re.compile(r"registry-sha256:\s*([0-9a-f]{64})")


def cmd_check(args: argparse.Namespace) -> int:
    registry_path = Path(args.registry)
    want = registry_sha256(registry_path)
    failed = 0
    for target in args.generated:
        path = Path(target)
        if not path.exists():
            print(f"  FAIL {path}: missing — run `make flags`")
            failed += 1
            continue
        match = SHA_RE.search(path.read_text(encoding="utf-8"))
        if not match:
            print(f"  FAIL {path}: no `registry-sha256:` provenance header")
            failed += 1
        elif match.group(1) != want:
            print(f"  FAIL {path}: generated from {match.group(1)[:12]}, registry is {want[:12]}")
            failed += 1
        else:
            print(f"  OK   {path}")
    if failed:
        print(f"DRIFT — {failed} projection(s) are stale. Run `make flags`.")
        return 1
    print(f"IN SYNC — {len(args.generated)} projection(s) match {registry_path} ({want[:12]}).")
    return 0


# --------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="flagsgen", description=__doc__.splitlines()[0])
    parser.add_argument("--version", action="version", version=f"flagsgen {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_validate = sub.add_parser("validate", help="validate a registry against the schema")
    p_validate.add_argument("--registry", required=True)
    p_validate.add_argument("--schema", required=True)
    p_validate.set_defaults(func=cmd_validate)

    p_js = sub.add_parser("emit-js", help="emit the browser resolver + dev toolbar")
    p_js.add_argument("--registry", required=True)
    p_js.add_argument("--out", required=True)
    p_js.add_argument("--dev-host", action="append", help="repeatable; overrides the default list")
    p_js.set_defaults(func=cmd_emit_js)

    p_env = sub.add_parser("emit-env", help="emit the build/deploy env projection")
    p_env.add_argument("--registry", required=True)
    p_env.add_argument("--out", required=True)
    p_env.set_defaults(func=cmd_emit_env)

    p_check = sub.add_parser("check", help="fail if a generated projection is stale")
    p_check.add_argument("--registry", required=True)
    p_check.add_argument("--generated", action="append", required=True)
    p_check.set_defaults(func=cmd_check)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
