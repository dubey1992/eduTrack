"""How much of the API the contract actually exercises.

Counted by watching the requests the suite makes, not by anyone ticking a list.
A hand-maintained tally would drift the first time a test was deleted, and the
number it reported would be the one nobody rechecked.

Concrete paths are reduced to their route shape - `students/42` and
`students/{student}` both become `students/{}` - so an observed call can be
matched against the manifest in `endpoints.py`.
"""

from __future__ import annotations

import re

from endpoints import ENDPOINTS, PYTHON_ONLY_ENDPOINTS

# Every (method, path) the suite has actually called this run. Filled in by
# Client._send, which is the only place a request is made.
CALLED: set[tuple[str, str]] = set()


def shape(path: str) -> str:
    """Strip the query string and normalise declared placeholders.

    `students/{student}` becomes `students/{}`. Concrete paths are left alone
    here, because a segment cannot be judged a parameter on its own - see
    `matches`.
    """
    path = path.split("?")[0].strip("/")

    return re.sub(r"\{[^}]+\}", "{}", path)


def matches(called: str, declared: str) -> bool:
    """Does a path that was called correspond to a declared route?

    Compared segment by segment, with a declared `{}` matching anything. String
    equality is not enough and the difference is not academic: route parameters
    are often not numbers - `imports/{type}` is called as `imports/students`,
    and `communication/templates/{event}` as `.../attendance.present` - so a
    normaliser that only reduced digits reported real coverage as a stale
    manifest.
    """
    a, b = called.split("/"), declared.split("/")

    if len(a) != len(b):
        return False

    return all(want == "{}" or want == got for got, want in zip(a, b))


# Set by the first contract test that finds the backend serves the Python-only
# endpoints, so a run against Laravel is not charged for what it never had.
PYTHON_ONLY_SERVED = False


def served() -> list[tuple[str, str]]:
    return ENDPOINTS + (PYTHON_ONLY_ENDPOINTS if PYTHON_ONLY_SERVED else [])


def record(method: str, path: str) -> None:
    CALLED.add((method.upper(), shape(path)))


def report() -> tuple[int, int, dict[str, list[str]]]:
    """Covered, total, and what is missing grouped by module."""
    declared = [(m.upper(), shape(u)) for m, u in served()]

    covered = {
        route
        for route in declared
        if any(method == route[0] and matches(path, route[1]) for method, path in CALLED)
    }

    missing: dict[str, list[str]] = {}
    for method, path in sorted(set(declared) - covered, key=lambda x: (x[1], x[0])):
        missing.setdefault(path.split("/")[0], []).append(f"{method} {path}")

    return len(covered), len(set(declared)), missing


def summarise() -> str:
    covered, total, missing = report()
    percent = (covered * 100) // total if total else 0

    lines = [f"Contract coverage: {covered}/{total} endpoints ({percent}%)"]

    if missing:
        lines.append("")
        lines.append("Not yet covered:")
        for module in sorted(missing):
            lines.append(f"  {module:<20} {len(missing[module])}")

    # Anything called that the manifest does not declare means the manifest is
    # stale, or a test is calling something that is not a real endpoint. The
    # Python-only list always counts as declared: probing whether a backend
    # serves it is not a wrong path.
    declared = [(m.upper(), shape(u)) for m, u in ENDPOINTS + PYTHON_ONLY_ENDPOINTS]
    unknown = sorted(
        call
        for call in CALLED
        if not any(call[0] == method and matches(call[1], path) for method, path in declared)
    )
    if unknown:
        lines.append("")
        lines.append("Called but not in the manifest (stale manifest, or a wrong path in a test):")
        lines.extend(f"  {m} {p}" for m, p in unknown)

    return "\n".join(lines)
