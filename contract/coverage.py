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

from endpoints import ENDPOINTS

# Every (method, path) the suite has actually called this run. Filled in by
# Client._send, which is the only place a request is made.
CALLED: set[tuple[str, str]] = set()


def shape(path: str) -> str:
    """Reduce a path to its route shape.

    `students/42?search=x` and `students/{student}` both come out as
    `students/{}`, which is what makes an observed call comparable to a
    declared route.
    """
    path = path.split("?")[0].strip("/")
    path = re.sub(r"\{[^}]+\}", "{}", path)

    # Any bare number is an id. Nothing in this API routes on a numeric
    # literal, so there is no real segment this can swallow by mistake.
    return re.sub(r"(?<=^)\d+(?=$)|(?<=/)\d+(?=/|$)", "{}", path)


def record(method: str, path: str) -> None:
    CALLED.add((method.upper(), shape(path)))


def report() -> tuple[int, int, dict[str, list[str]]]:
    """Covered, total, and what is missing grouped by module."""
    declared = {(m.upper(), shape(u)) for m, u in ENDPOINTS}
    covered = declared & CALLED

    missing: dict[str, list[str]] = {}
    for method, path in sorted(declared - covered, key=lambda x: (x[1], x[0])):
        missing.setdefault(path.split("/")[0], []).append(f"{method} {path}")

    return len(covered), len(declared), missing


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
    # stale, or a test is calling something that is not a real endpoint.
    declared = {(m.upper(), shape(u)) for m, u in ENDPOINTS}
    unknown = sorted(CALLED - declared)
    if unknown:
        lines.append("")
        lines.append("Called but not in the manifest (stale manifest, or a wrong path in a test):")
        lines.extend(f"  {m} {p}" for m, p in unknown)

    return "\n".join(lines)
