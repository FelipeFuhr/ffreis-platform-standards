#!/usr/bin/env python3
"""Report what a metric registry actually proves, and what it only claims.

`validate-metric-registry.py` answers "is this registry well formed and
internally consistent". It cannot answer the question a reader of a report
actually has: **which of these numbers is still being produced by something?**

A registry satisfies the validator with every single metric carrying a reasoned
exception — that is legal, and it is also a project where nothing proves any
published number still works. The exceptions are the honest record of that, so
the useful output is not pass/fail but a shape: how much is covered, how much is
carried by exception, how old the exceptions are, and — the one real failure
mode — whether any `coverage` id points at a scenario that no longer exists.

That last one is why this exits non-zero. A scenario rename or deletion
silently un-covers every metric that named it: the registry keeps asserting
coverage, the validator keeps passing, and nothing runs. It is the metric
registry's version of the gap the standard was written to close, one level up.

Usage:
    metric-coverage-report.py REGISTRY... [--scenarios DIR] [--json]

`--scenarios` points at the scenario corpus — a directory whose filenames (sans
extension, and sans a trailing `.spec`) are the ids a registry's `coverage`
field uses. Omit it to skip the dangling/unused checks, which are the only ones
that can fail.

Exit: 0 clean · 1 a coverage id points at no scenario · 2 usage or unreadable
input.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path
from typing import Any

#: An exception older than this is worth re-reading: the reason was written
#: about a situation that may no longer hold. Not a failure — a prompt.
STALE_EXCEPTION_DAYS = 180

#: Suffixes stripped from a scenario filename to get its id. `.spec` is the
#: Playwright/vitest convention and is not part of the id a registry names.
_SCENARIO_SUFFIXES = (".spec",)
_SCENARIO_EXTENSIONS = (".ts", ".js", ".mjs", ".py", ".rs", ".json", ".yaml", ".yml")


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def scenario_ids(root: Path) -> set[str]:
    """Every scenario id the corpus at `root` offers.

    Recurses, because a corpus is commonly grouped into subdirectories and the
    id is the filename rather than the path.
    """
    ids: set[str] = set()
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in _SCENARIO_EXTENSIONS:
            continue
        stem = path.stem
        for suffix in _SCENARIO_SUFFIXES:
            if stem.endswith(suffix):
                stem = stem[: -len(suffix)]
        ids.add(stem)
    return ids


def days_old(added: Any, today: date) -> int | None:
    if not isinstance(added, str):
        return None
    try:
        return (today - date.fromisoformat(added)).days
    except ValueError:
        return None


class Assessment:
    """What one registry proves, broken down the way a reader needs it."""

    def __init__(self, path: Path, registry: dict, today: date) -> None:
        self.path = path
        self.project = registry.get("project") or path.parent.parent.name
        metrics = registry.get("metrics") or []
        self.total = len(metrics)

        self.covered: list[str] = []
        self.by_exception: list[str] = []
        self.vacuous: list[str] = []
        #: coverage id -> the metrics that name it. A broken scenario's blast
        #: radius, which is invisible from either side alone.
        self.referenced: dict[str, list[str]] = {}
        #: (metric, scope, reason, age) for every reasoned exception.
        self.exceptions: list[tuple[str, str, str, int | None]] = []
        self.surfaces: dict[str, list[int]] = {}
        self.populations: dict[str, int] = {}

        for metric in metrics:
            if not isinstance(metric, dict):
                continue
            name = str(metric.get("name", "<unnamed>"))
            coverage = metric.get("coverage") or []
            exceptions = [e for e in metric.get("exceptions") or [] if isinstance(e, dict)]

            if coverage:
                self.covered.append(name)
                for scenario in coverage:
                    self.referenced.setdefault(str(scenario), []).append(name)
            elif exceptions:
                self.by_exception.append(name)
            else:
                # The validator rejects this, so reaching it means the registry
                # was not validated. Reported rather than assumed away.
                self.vacuous.append(name)

            for exception in exceptions:
                self.exceptions.append(
                    (
                        name,
                        str(exception.get("scope", "")),
                        str(exception.get("reason", "")),
                        days_old(exception.get("added"), today),
                    )
                )

            surface = str(metric.get("surface", "<none>"))
            tally = self.surfaces.setdefault(surface, [0, 0])
            tally[0] += 1
            if coverage:
                tally[1] += 1

            population = str(metric.get("population", "<none>"))
            self.populations[population] = self.populations.get(population, 0) + 1

    @property
    def coverage_pct(self) -> float | None:
        """Share of declared metrics a scenario actually exercises.

        `None` rather than 0 for an empty registry: a share of nothing is not
        zero percent covered, and printing 0% would read as a finding.
        """
        if self.total == 0:
            return None
        return round(len(self.covered) * 100 / self.total, 1)

    def dangling(self, known: set[str]) -> dict[str, list[str]]:
        """Coverage ids with no scenario behind them, and who named them."""
        return {
            scenario: metrics
            for scenario, metrics in sorted(self.referenced.items())
            if scenario not in known
        }

    def unused(self, known: set[str]) -> list[str]:
        """Scenarios no metric names. Not a failure — possibly a missing entry."""
        return sorted(known - set(self.referenced))

    def stale(self) -> list[tuple[str, str, int]]:
        return sorted(
            (name, scope, age)
            for name, scope, _reason, age in self.exceptions
            if age is not None and age > STALE_EXCEPTION_DAYS
        )

    def to_dict(self, known: set[str] | None) -> dict[str, Any]:
        out: dict[str, Any] = {
            "project": self.project,
            "registry": str(self.path),
            "total": self.total,
            "covered": len(self.covered),
            "by_exception": len(self.by_exception),
            "vacuous": self.vacuous,
            "coverage_pct": self.coverage_pct,
            "surfaces": {s: {"total": t, "covered": c} for s, (t, c) in self.surfaces.items()},
            "populations": self.populations,
            "scenarios": {s: len(m) for s, m in sorted(self.referenced.items())},
            "stale_exceptions": [
                {"metric": n, "scope": s, "age_days": a} for n, s, a in self.stale()
            ],
        }
        if known is not None:
            out["dangling_coverage"] = self.dangling(known)
            out["unused_scenarios"] = self.unused(known)
        return out


def bar(covered: int, total: int, width: int = 24) -> str:
    if total == 0:
        return "-" * width
    filled = round(covered * width / total)
    return "#" * filled + "." * (width - filled)


def render(assessment: Assessment, known: set[str] | None) -> list[str]:
    lines = [f"{assessment.project}  ({assessment.path})"]
    pct = assessment.coverage_pct
    shown = "n/a" if pct is None else f"{pct}%"
    lines.append(
        f"  coverage   [{bar(len(assessment.covered), assessment.total)}] "
        f"{len(assessment.covered)}/{assessment.total} metrics  ({shown})"
    )
    if assessment.by_exception:
        lines.append(
            f"  exception  {len(assessment.by_exception)} metric(s) carried by a reasoned "
            "exception — declared, not proven"
        )
    if assessment.vacuous:
        lines.append(
            f"  VACUOUS    {len(assessment.vacuous)} metric(s) with neither coverage nor a "
            "reasoned exception: " + ", ".join(assessment.vacuous)
        )
        lines.append(
            "             (the validator rejects these, so this registry is not gated)"
        )

    lines.append("  per surface:")
    for surface, (total, covered) in sorted(assessment.surfaces.items()):
        lines.append(f"    {surface:<24} {covered}/{total}")

    if assessment.populations:
        parts = ", ".join(f"{p}={n}" for p, n in sorted(assessment.populations.items()))
        lines.append(f"  populations: {parts}")

    if assessment.referenced:
        lines.append("  scenarios, by how many metrics depend on them:")
        for scenario, metrics in sorted(
            assessment.referenced.items(), key=lambda kv: (-len(kv[1]), kv[0])
        ):
            mark = "" if known is None or scenario in known else "   <- NO SUCH SCENARIO"
            lines.append(f"    {scenario:<32} {len(metrics)}{mark}")

    if known is not None:
        unused = assessment.unused(known)
        if unused:
            lines.append(
                "  scenarios no metric names (a corpus entry, or a missing registry "
                "entry): " + ", ".join(unused)
            )

    stale = assessment.stale()
    if stale:
        lines.append(f"  exceptions older than {STALE_EXCEPTION_DAYS} days:")
        for name, scope, age in stale:
            lines.append(f"    {name} ({scope}) — {age} days")
    return lines


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("registries", nargs="+", metavar="REGISTRY")
    parser.add_argument(
        "--scenarios",
        type=Path,
        default=None,
        help="directory of scenario files whose names are the coverage ids",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    known: set[str] | None = None
    if args.scenarios is not None:
        if not args.scenarios.is_dir():
            print(f"ERROR: --scenarios {args.scenarios} is not a directory", file=sys.stderr)
            return 2
        known = scenario_ids(args.scenarios)
        if not known:
            print(
                f"ERROR: no scenario files under {args.scenarios} — an empty corpus would "
                "mark every coverage id dangling, which is a tooling failure rather than "
                "a finding",
                file=sys.stderr,
            )
            return 2

    today = date.today()
    assessments: list[Assessment] = []
    for name in args.registries:
        path = Path(name)
        try:
            registry = load_json(path)
        except (OSError, json.JSONDecodeError) as error:
            print(f"ERROR: cannot read {path}: {error}", file=sys.stderr)
            return 2
        if not isinstance(registry, dict):
            print(f"ERROR: {path} is not a JSON object", file=sys.stderr)
            return 2
        assessments.append(Assessment(path, registry, today))

    if args.json:
        print(json.dumps([a.to_dict(known) for a in assessments], indent=2))
    else:
        for assessment in assessments:
            for line in render(assessment, known):
                print(line)
            print()

    if known is None:
        return 0

    broken = 0
    for assessment in assessments:
        for scenario, metrics in assessment.dangling(known).items():
            broken += 1
            print(
                f"FAIL {assessment.project}: coverage id `{scenario}` matches no scenario, "
                f"so {len(metrics)} metric(s) claim a proof that does not exist: "
                + ", ".join(metrics),
                file=sys.stderr,
            )
    if broken:
        print(
            f"\n{broken} dangling coverage id(s). Rename the scenario back, or move those "
            "metrics to a reasoned exception — a registry must not assert a proof it "
            "has not got.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
