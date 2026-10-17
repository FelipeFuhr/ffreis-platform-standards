#!/usr/bin/env python3
"""Validate a flag registry (flags/flags.json) against the fleet's schema.

Checks two layers:

1. **Structural** — required keys, enum membership, unknown properties, and the
   conditional requirements (route needs options, value needs value_type, …).
2. **Semantic conformance** — the rules JSON Schema cannot express, which are
   the ones that actually keep the registry honest:
     * a `category: quality` entry claiming enforcement must name its gate in
       `seam`; one that does not enforce must carry a reasoned exception
     * an `exceptions` reason must be a real reason, not a placeholder
     * a `category: model` route flag must default to its least-real option
       (the fleet's cost guard) unless an exception justifies otherwise

Every enum, required-key list and property name is **extracted from the schema
at runtime**, and the quality-rule vocabulary is extracted from the `###`
headings in flags/quality-rules.md. Nothing here keeps its own copy: a copy is
how the validator and the artifacts it validates drift apart while both still
pass. Deliberately dependency-free (no jsonschema) so a consumer repo can
vendor this file plus the two artifacts and gate its own registry.

Usage:
    validate-flag-registry.py [--schema PATH] [--vocabulary PATH] REGISTRY...

Exit: 0 all valid · 1 findings reported · 2 usage or unreadable input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

# A reason that is one of these, or shorter than this, explains nothing. The
# floor is deliberately low — it rejects "TODO"/"later", not a terse-but-real
# reason like "the token definition file".
PLACEHOLDER_REASONS = frozenset(
    {"", "todo", "tbd", "n/a", "na", "none", "later", "fixme", "wip", "?", "-"}
)
MIN_REASON_CHARS = 15

# Values of `default` that mean "this rule is actively enforced". Anything else
# (false, "off") means it is not, which is what triggers the justify-it branch.
ENFORCING_DEFAULTS = frozenset({True, "error", "warn"})

RULE_HEADING_RE = re.compile(r"^###\s+`([^`]+)`\s*$", re.MULTILINE)
RULE_ID_RE = re.compile(r"^[a-z][a-z0-9-]*$")


class SchemaFacts:
    """The parts of the schema the validator reads, pulled out once."""

    def __init__(self, schema: dict) -> None:
        defs = schema.get("$defs", {})
        flag = defs.get("flag", {})
        props = flag.get("properties", {})

        self.top_required: list[str] = schema.get("required", [])
        self.top_properties: set[str] = set(schema.get("properties", {}).keys())
        self.flag_required: list[str] = flag.get("required", [])
        self.flag_properties: set[str] = set(props.keys())
        self.name_pattern: str = props.get("name", {}).get("pattern", ".*")
        self.enums: dict[str, list] = {
            field: props.get(field, {}).get("enum", [])
            for field in ("kind", "category", "binding", "effect", "value_type", "scope")
        }
        self.output_targets: list[str] = defs.get("outputTarget", {}).get("enum", [])
        self.exception_required: list[str] = defs.get("exception", {}).get("required", [])
        self.exception_properties: set[str] = set(
            defs.get("exception", {}).get("properties", {}).keys()
        )

    def missing_pieces(self) -> list[str]:
        """Report anything the extractor could not find.

        A silently-empty enum would make every value look valid, so an
        extraction failure must be loud rather than permissive.
        """
        gaps = []
        if not self.flag_required:
            gaps.append("$defs.flag.required")
        if not self.flag_properties:
            gaps.append("$defs.flag.properties")
        if not self.output_targets:
            gaps.append("$defs.outputTarget.enum")
        if not self.exception_required:
            gaps.append("$defs.exception.required")
        gaps += [f"$defs.flag.properties.{f}.enum" for f, v in self.enums.items() if not v]
        return gaps


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_vocabulary(path: Path) -> tuple[set[str], list[str]]:
    """Return the rule ids, plus any problems with the vocabulary file itself.

    A heading that looks like a rule but is not a well-formed id is reported
    rather than skipped. Skipping registers no rule, and the only symptom
    would be a later "not in the vocabulary" rejection pointing at the
    registry — sending the reader to the wrong file to find a typo that is
    here. A duplicate id is reported for the same reason: harmless to the set,
    but always a copy-paste error worth surfacing.
    """
    headings = RULE_HEADING_RE.findall(path.read_text(encoding="utf-8"))
    problems = [f"malformed rule id `{h}` (must match {RULE_ID_RE.pattern})"
                for h in headings if not RULE_ID_RE.fullmatch(h)]
    problems += [f"duplicate rule id `{h}`"
                 for h, count in sorted(Counter(headings).items()) if count > 1]
    return {h for h in headings if RULE_ID_RE.fullmatch(h)}, problems


def is_placeholder(reason: str) -> bool:
    collapsed = " ".join(reason.split()).strip()
    if collapsed.lower().rstrip(".") in PLACEHOLDER_REASONS:
        return True
    return len(collapsed) < MIN_REASON_CHARS


def check_top_level(registry: dict, facts: SchemaFacts) -> list[str]:
    findings = []
    for key in facts.top_required:
        if key not in registry:
            findings.append(f"registry is missing required key `{key}`")
    for key in sorted(set(registry) - facts.top_properties):
        findings.append(f"registry has unknown key `{key}`")
    if "version" in registry and registry["version"] != 1:
        findings.append(f"registry version must be 1, got {registry['version']!r}")
    if not isinstance(registry.get("flags", []), list):
        findings.append("`flags` must be an array")
    return findings


def check_shape(flag: dict, label: str, facts: SchemaFacts) -> list[str]:
    """Required keys, unknown keys, name pattern and enum membership."""
    findings = []
    for key in facts.flag_required:
        if key not in flag:
            findings.append(f"{label}: missing required key `{key}`")
    for key in sorted(set(flag) - facts.flag_properties):
        findings.append(f"{label}: unknown key `{key}`")

    name = flag.get("name")
    if isinstance(name, str) and not re.fullmatch(facts.name_pattern, name):
        findings.append(f"{label}: name {name!r} does not match {facts.name_pattern}")

    for field, allowed in facts.enums.items():
        value = flag.get(field)
        if value is not None and value not in allowed:
            findings.append(f"{label}: {field}={value!r} is not one of {allowed}")

    targets = flag.get("output_target")
    if targets is not None:
        listed = targets if isinstance(targets, list) else [targets]
        for target in listed:
            if target not in facts.output_targets:
                findings.append(
                    f"{label}: output_target={target!r} is not one of {facts.output_targets}"
                )
    return findings


def check_conditionals(flag: dict, label: str) -> list[str]:
    findings = []
    options = flag.get("options")
    if flag.get("effect") == "route":
        if not options:
            findings.append(f"{label}: effect=route requires `options`")
        elif len(options) < 2:
            findings.append(f"{label}: effect=route requires at least 2 options")
    if flag.get("kind") == "value" and "value_type" not in flag:
        findings.append(f"{label}: kind=value requires `value_type`")
    if flag.get("kind") == "gate" and flag.get("effect") != "toggle":
        findings.append(f"{label}: kind=gate must have effect=toggle")
    if options and "default" in flag and flag["default"] not in options:
        findings.append(
            f"{label}: default {flag['default']!r} is not one of its options {options}"
        )
    return findings


def check_exceptions(flag: dict, label: str, facts: SchemaFacts) -> list[str]:
    findings = []
    for index, exception in enumerate(flag.get("exceptions", [])):
        where = f"{label}: exceptions[{index}]"
        if not isinstance(exception, dict):
            findings.append(f"{where} must be an object")
            continue
        for key in facts.exception_required:
            if key not in exception:
                findings.append(f"{where} is missing required key `{key}`")
        for key in sorted(set(exception) - facts.exception_properties):
            findings.append(f"{where} has unknown key `{key}`")
        reason = exception.get("reason")
        if isinstance(reason, str) and is_placeholder(reason):
            findings.append(
                f"{where} reason {reason!r} explains nothing — state why the rule "
                f"does not apply (≥{MIN_REASON_CHARS} chars, not a placeholder)"
            )
    return findings


def check_quality(flag: dict, label: str, vocabulary: set[str]) -> list[str]:
    """The conformance rules that keep a quality declaration honest."""
    if flag.get("category") != "quality":
        if "rule" in flag:
            return [f"{label}: `rule` is only meaningful for category=quality"]
        return []

    findings = []
    rule = flag.get("rule")
    if rule is None:
        findings.append(f"{label}: category=quality requires `rule`")
    elif rule not in vocabulary:
        findings.append(
            f"{label}: rule {rule!r} is not in the vocabulary — add a `### `{rule}`` "
            f"section to flags/quality-rules.md or fix the typo "
            f"(known: {sorted(vocabulary)})"
        )

    enforcing = flag.get("default") in ENFORCING_DEFAULTS
    seam = (flag.get("seam") or "").strip()
    has_reasoned_exception = bool(flag.get("exceptions"))

    if enforcing and not seam:
        findings.append(
            f"{label}: claims enforcement (default={flag.get('default')!r}) but names no "
            f"`seam` — point at the test, check rule or CI step that enforces it"
        )
    if not enforcing and not has_reasoned_exception:
        findings.append(
            f"{label}: does not enforce (default={flag.get('default')!r}) and gives no "
            f"reason — add an `exceptions` entry saying why, so the gap is declared "
            f"rather than silent"
        )
    return findings


def check_cost_guard(flag: dict, label: str) -> list[str]:
    """Model flags must default to the least-real option unless justified.

    The schema documents `options` as ordered least-real -> most-real, so the
    cheapest choice is options[0]. This is the fleet's standing cost guard
    ("never bill a paid backend from an unconfigured toolbar"), which until now
    was documented but unenforced.
    """
    if flag.get("category") != "model" or flag.get("effect") != "route":
        return []
    options = flag.get("options") or []
    if not options or "default" not in flag:
        return []
    if flag["default"] == options[0] or flag.get("exceptions"):
        return []
    return [
        f"{label}: model flag defaults to {flag['default']!r} but its cheapest option is "
        f"{options[0]!r} — default to the cheapest, or declare an `exceptions` entry "
        f"justifying the cost"
    ]


def validate(registry: dict, facts: SchemaFacts, vocabulary: set[str]) -> list[str]:
    findings = check_top_level(registry, facts)
    flags = registry.get("flags", [])
    if not isinstance(flags, list):
        return findings

    seen: dict[str, int] = {}
    for index, flag in enumerate(flags):
        label = f"flags[{index}]"
        if not isinstance(flag, dict):
            findings.append(f"{label} must be an object")
            continue
        name = flag.get("name")
        if isinstance(name, str):
            label = f"flag `{name}`"
            if name in seen:
                findings.append(f"{label}: duplicate name (also at flags[{seen[name]}])")
            else:
                seen[name] = index
        findings += check_shape(flag, label, facts)
        findings += check_conditionals(flag, label)
        findings += check_exceptions(flag, label, facts)
        findings += check_quality(flag, label, vocabulary)
        findings += check_cost_guard(flag, label)
    return findings


def parse_args(argv: list[str]) -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    flags_dir = here.parent / "flags"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("registries", nargs="+", metavar="REGISTRY")
    parser.add_argument("--schema", type=Path, default=flags_dir / "flag-registry.schema.json")
    parser.add_argument("--vocabulary", type=Path, default=flags_dir / "quality-rules.md")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        facts = SchemaFacts(load_json(args.schema))
        vocabulary, vocabulary_problems = load_vocabulary(args.vocabulary)
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read schema/vocabulary: {error}", file=sys.stderr)
        return 2

    if vocabulary_problems:
        print(f"ERROR: {args.vocabulary} is malformed:", file=sys.stderr)
        for problem in vocabulary_problems:
            print(f"       {problem}", file=sys.stderr)
        return 2

    gaps = facts.missing_pieces()
    if gaps:
        print(
            "ERROR: could not extract from the schema: "
            + ", ".join(gaps)
            + "\n       The schema was probably restructured — update SchemaFacts.",
            file=sys.stderr,
        )
        return 2
    if not vocabulary:
        print(
            f"ERROR: no quality rules found in {args.vocabulary} — expected "
            "`### `rule-id`` headings.",
            file=sys.stderr,
        )
        return 2

    total = 0
    for name in args.registries:
        path = Path(name)
        try:
            registry = load_json(path)
        except (OSError, json.JSONDecodeError) as error:
            print(f"  FAIL {path}: {error}", file=sys.stderr)
            total += 1
            continue
        findings = validate(registry, facts, vocabulary)
        if findings:
            print(f"  FAIL {path}")
            for finding in findings:
                print(f"         {finding}")
            total += len(findings)
        else:
            count = len(registry.get("flags", []))
            print(f"  OK   {path} ({count} flag{'s' if count != 1 else ''})")

    if total:
        print(f"\n{total} finding(s).", file=sys.stderr)
        return 1
    print(f"All {len(args.registries)} registry file(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
