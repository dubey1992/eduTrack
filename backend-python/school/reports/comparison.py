"""The previous-period comparison a report carries when asked for one.

Phase 20: every figure a report states can be read against the same-length
period just before it (ReportRange.previous). The report is simply built a
second time over that range, so the two halves are computed by exactly the
same rules - nothing here re-derives a figure.

What goes out, only when `compare=1` is asked for:

- `comparison.range` and `comparison.totals` - the previous period's range and
  its totals, whole, so a group can recombine them from raw counts.
- `previous` on every row - the previous value of each of the report's
  COMPARED_ROWS, or null when the row did not exist then (a student admitted
  since, a route set up since).

A report with no COMPARED_ROWS still gets `comparison`; its rows get nothing.
"""

from __future__ import annotations


def attach(report, current: dict, previous: dict) -> dict:
    current["comparison"] = {"range": previous["range"], "totals": previous["totals"]}

    keys = [key for key, _ in report.COMPARED_ROWS]
    if not keys:
        return current

    before = {report.row_key(row): row for row in previous["rows"]}

    for row in current["rows"]:
        earlier = before.get(report.row_key(row))
        row["previous"] = {key: None if earlier is None else earlier.get(key) for key in keys}

    return current


def headings(report) -> list[str]:
    """The extra export columns, after the report's own."""
    return [f"{heading} (previous period)" for _, heading in report.COMPARED_ROWS]


def cells(report, row: dict) -> list:
    previous = row.get("previous") or {}
    return [previous.get(key) for key, _ in report.COMPARED_ROWS]
