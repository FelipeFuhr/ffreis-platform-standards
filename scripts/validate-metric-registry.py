#!/usr/bin/env python3
"""Validate a metric registry (metrics/metrics.json) against the fleet's schema.

Checks two layers:

1. **Structural** — required keys, enum membership, unknown properties, and the
   conditional requirements (a rate needs a denominator, a distribution needs a
   minimum sample, …).
2. **Semantic conformance** — the rules JSON Schema cannot express, which are
   the ones that actually keep a published number honest:
     * `denominator` and `baseline` must RESOLVE to declared metrics, and a
       baseline must be an `all-traffic` one — a reference that points nowhere
       is the same as no denominator at all
     * a `consenting-visitor` metric must name that baseline, because telemetry
       that only fires after consent cannot measure who refused, and a reader
       shown only the consenting sample reads it as the traffic
     * a metric with no `coverage` must carry a reasoned exception — otherwise
       nothing proves it still works, and it is vacuous
     * a `mixed` population must say in `description` what it mixes
     * an `exceptions` reason must be a real reason, not a placeholder

Every enum, required-key list and property name is **extracted from the schema
at runtime**. Nothing here keeps its own copy: a copy is how the validator and
the artifact it validates drift apart while both still pass. Deliberately
dependency-free (no jsonschema) so a consumer repo can vendor this file plus
the schema and gate its own registry.

Usage:
    validate-metric-registry.py [--schema PATH] REGISTRY...

Exit: 0 all valid · 1 findings reported · 2 usage or unreadable input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# A reason that is one of these, or shorter than this, explains nothing. The
# floor is deliberately low — it rejects "TODO"/"later", not a terse-but-real
# reason like "edge metric, no sample to speak of".
PLACEHOLDER_REASONS = frozenset(
    {"", "todo", "tbd", "n/a", "na", "none", "later", "fixme", "wip", "?", "-"}
)
MIN_REASON_CHARS = 15

# The population that can stand as a denominator for any other: it is measured
# without needing the visitor's cooperation, so it has no selection gap.
BASELINE_POPULATION = "all-traffic"

# Populations that are a subset of the people their surface appears to describe,
# and so cannot be read on their own.
SUBSET_POPULATIONS = frozenset({"consenting-visitor"})

# Kinds that are a part over a whole and therefore need to name the whole.
QUOTIENT_KINDS = frozenset({"rate", "ratio"})


class SchemaFacts:
    """The parts of the schema the validator reads, pulled out once."""

    def __init__(self, schema: dict) -> None:
        defs = schema.get("$defs", {})
        metric = defs.get("metric", {})
        props = metric.get("properties", {})

        self.top_required: list[str] = schema.get("required", [])
        self.top_properties: set[str] = set(schema.get("properties", {}).keys())
        self.metric_required: list[str] = metric.get("required", [])
        self.metric_properties: set[str] = set(props.keys())
        self.name_pattern: str = props.get("name", {}).get("pattern", ".*")
        self.kinds: list[str] = props.get("kind", {}).get("enum", [])
        # `population` and `source` are $refs, so their facts live under $defs.
        self.populations: list[str] = defs.get("population", {}).get("enum", [])
        self.source_required: list[str] = defs.get("source", {}).get("required", [])
        self.source_properties: set[str] = set(defs.get("source", {}).get("properties", {}).keys())
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
        if not self.metric_required:
            gaps.append("$defs.metric.required")
        if not self.metric_properties:
            gaps.append("$defs.metric.properties")
        if not self.kinds:
            gaps.append("$defs.metric.properties.kind.enum")
        if not self.populations:
            gaps.append("$defs.population.enum")
        if not self.source_required:
            gaps.append("$defs.source.required")
        if not self.exception_required:
            gaps.append("$defs.exception.required")
        return gaps


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def is_placeholder(text: str) -> bool:
    collapsed = " ".join(text.split()).strip()
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
    if not isinstance(registry.get("metrics", []), list):
        findings.append("`metrics` must be an array")
    return findings


def check_shape(metric: dict, label: str, facts: SchemaFacts) -> list[str]:
    """Required keys, unknown keys, name pattern, enum membership, types."""
    findings = []
    for key in facts.metric_required:
        if key not in metric:
            findings.append(f"{label}: missing required key `{key}`")
    for key in sorted(set(metric) - facts.metric_properties):
        findings.append(f"{label}: unknown key `{key}`")

    name = metric.get("name")
    if isinstance(name, str) and not re.fullmatch(facts.name_pattern, name):
        findings.append(f"{label}: name {name!r} does not match {facts.name_pattern}")

    kind = metric.get("kind")
    if kind is not None and kind not in facts.kinds:
        findings.append(f"{label}: kind={kind!r} is not one of {facts.kinds}")

    population = metric.get("population")
    if population is not None and population not in facts.populations:
        findings.append(
            f"{label}: population={population!r} is not one of {facts.populations}"
        )

    sample = metric.get("min_sample")
    if sample is not None and (not isinstance(sample, int) or isinstance(sample, bool) or sample < 0):
        findings.append(f"{label}: min_sample must be a non-negative integer, got {sample!r}")

    coverage = metric.get("coverage")
    if coverage is not None:
        if not isinstance(coverage, list) or not all(isinstance(c, str) for c in coverage):
            findings.append(f"{label}: coverage must be an array of scenario ids")
        elif not coverage:
            findings.append(f"{label}: coverage is present but empty — omit it or name a scenario")
    return findings


def check_source(metric: dict, label: str, facts: SchemaFacts) -> list[str]:
    findings = []
    source = metric.get("source")
    if source is None:
        return findings
    if not isinstance(source, dict):
        return [f"{label}: source must be an object"]
    for key in facts.source_required:
        if key not in source:
            findings.append(f"{label}: source is missing required key `{key}`")
    for key in sorted(set(source) - facts.source_properties):
        findings.append(f"{label}: source has unknown key `{key}`")
    signal = source.get("signal")
    if isinstance(signal, str) and not signal.strip():
        findings.append(f"{label}: source.signal is blank — name the event, field or query")
    excludes = source.get("excludes")
    if excludes is not None and (
        not isinstance(excludes, list) or not all(isinstance(e, str) for e in excludes)
    ):
        findings.append(f"{label}: source.excludes must be an array of strings")
    return findings


def check_conditionals(metric: dict, label: str) -> list[str]:
    """The schema's allOf branches, plus the inverses it cannot express."""
    findings = []
    kind = metric.get("kind")
    population = metric.get("population")

    if kind in QUOTIENT_KINDS:
        if "denominator" not in metric:
            findings.append(f"{label}: kind={kind} requires `denominator` — name what it is over")
        if "min_sample" not in metric:
            findings.append(f"{label}: kind={kind} requires `min_sample`")
    if kind == "distribution" and "min_sample" not in metric:
        findings.append(
            f"{label}: kind=distribution requires `min_sample` — a percentile over one "
            "observation is that observation wearing a statistic's name"
        )
    if kind == "count" and "denominator" in metric:
        findings.append(
            f"{label}: kind=count must not carry `denominator` — a tally is not taken over "
            "anything; declare it as a rate or a ratio if it is"
        )

    if population in SUBSET_POPULATIONS and "baseline" not in metric:
        findings.append(
            f"{label}: population={population} requires `baseline` — this sample cannot "
            "measure whoever is missing from it, so it cannot be its own denominator"
        )
    if population == BASELINE_POPULATION and "baseline" in metric:
        findings.append(
            f"{label}: population={BASELINE_POPULATION} must not carry `baseline` — it is "
            "already the population a baseline would point at"
        )
    if population == "mixed":
        description = metric.get("description")
        if not isinstance(description, str) or is_placeholder(description):
            findings.append(
                f"{label}: population=mixed requires a `description` saying what it mixes "
                f"(≥{MIN_REASON_CHARS} chars) — a blended population is legitimate for a "
                "pipeline-health number and misleading for a behavioural one"
            )
    return findings


def check_references(metric: dict, label: str, declared: dict[str, dict]) -> list[str]:
    """`denominator` and `baseline` must point at real, suitable metrics."""
    findings = []
    name = metric.get("name")

    denominator = metric.get("denominator")
    if isinstance(denominator, str):
        if denominator == name:
            findings.append(f"{label}: denominator refers to itself")
        elif denominator not in declared:
            findings.append(
                f"{label}: denominator `{denominator}` is not a declared metric"
            )

    baseline = metric.get("baseline")
    if isinstance(baseline, str):
        if baseline == name:
            findings.append(f"{label}: baseline refers to itself")
        elif baseline not in declared:
            findings.append(f"{label}: baseline `{baseline}` is not a declared metric")
        else:
            baseline_population = declared[baseline].get("population")
            if baseline_population != BASELINE_POPULATION:
                findings.append(
                    f"{label}: baseline `{baseline}` has population "
                    f"{baseline_population!r}, not {BASELINE_POPULATION!r} — a baseline "
                    "measured the same way carries the same blind spot"
                )
    return findings


def check_coverage(metric: dict, label: str) -> list[str]:
    """Covered, or a reasoned exception saying why not. Never silently neither."""
    if metric.get("coverage"):
        return []
    reasoned = [
        exception
        for exception in metric.get("exceptions", [])
        if isinstance(exception, dict)
        and isinstance(exception.get("reason"), str)
        and not is_placeholder(exception["reason"])
    ]
    if reasoned:
        return []
    return [
        f"{label}: no `coverage` and no reasoned exception — nothing proves this number "
        "is still produced, so it is vacuous. Name a scenario, or declare why it has none."
    ]


def check_exceptions(metric: dict, label: str, facts: SchemaFacts) -> list[str]:
    findings = []
    exceptions = metric.get("exceptions")
    if exceptions is None:
        return findings
    if not isinstance(exceptions, list):
        return [f"{label}: exceptions must be an array"]
    for index, exception in enumerate(exceptions):
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
                f"{where} reason {reason!r} explains nothing — state why the requirement "
                f"does not apply (≥{MIN_REASON_CHARS} chars, not a placeholder)"
            )
    return findings


def validate(registry: dict, facts: SchemaFacts) -> list[str]:
    findings = check_top_level(registry, facts)
    metrics = registry.get("metrics", [])
    if not isinstance(metrics, list):
        return findings

    # Reference checks need every name up front, so a metric may cite one
    # declared after it.
    declared: dict[str, dict] = {
        m["name"]: m for m in metrics if isinstance(m, dict) and isinstance(m.get("name"), str)
    }

    seen: dict[str, int] = {}
    for index, metric in enumerate(metrics):
        label = f"metrics[{index}]"
        if not isinstance(metric, dict):
            findings.append(f"{label} must be an object")
            continue
        name = metric.get("name")
        if isinstance(name, str):
            label = f"metric `{name}`"
            if name in seen:
                findings.append(f"{label}: duplicate name (also at metrics[{seen[name]}])")
            else:
                seen[name] = index
        findings += check_shape(metric, label, facts)
        findings += check_source(metric, label, facts)
        findings += check_conditionals(metric, label)
        findings += check_references(metric, label, declared)
        findings += check_coverage(metric, label)
        findings += check_exceptions(metric, label, facts)
    return findings


def parse_args(argv: list[str]) -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    metrics_dir = here.parent / "metrics"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("registries", nargs="+", metavar="REGISTRY")
    parser.add_argument(
        "--schema", type=Path, default=metrics_dir / "metric-registry.schema.json"
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        facts = SchemaFacts(load_json(args.schema))
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read schema: {error}", file=sys.stderr)
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

    total = 0
    for name in args.registries:
        path = Path(name)
        try:
            registry = load_json(path)
        except (OSError, json.JSONDecodeError) as error:
            print(f"  FAIL {path}: {error}", file=sys.stderr)
            total += 1
            continue
        findings = validate(registry, facts)
        if findings:
            print(f"  FAIL {path}")
            for finding in findings:
                print(f"         {finding}")
            total += len(findings)
        else:
            count = len(registry.get("metrics", []))
            print(f"  OK   {path} ({count} metric{'s' if count != 1 else ''})")

    if total:
        print(f"\n{total} finding(s).", file=sys.stderr)
        return 1
    print(f"All {len(args.registries)} registry file(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
