"""Any report as a printable PDF (Phase 20).

The same figures as the screen and the CSV - the rows are the report's own
csv_rows(), so the three can never disagree - laid out for a printer:
landscape A4, the school and period at the top, the totals (with the previous
period beside them when a comparison was asked for), then the table.

Rendered with xhtml2pdf like receipts and payslips, for the same reason:
shared hosting has no cairo or pango. That also means simple tables and the
receipt's stylesheet, nothing cleverer.
"""

from __future__ import annotations

import html
import io
from decimal import Decimal

from xhtml2pdf import pisa

from .. import money
from ..receipts import STYLESHEET, e
from . import comparison

DEFAULT_NOTE = "Every rate is out of the days the school actually ran: weekends and the school's holidays are not counted."

REPORT_STYLES = """
@page { size: a4 landscape; margin: 14mm 12mm; }
.sheet { padding: 0; }
.grid { margin-top: 10px; border: 1px solid #d7dbe3; }
.grid th { background: #f3f4f6; text-align: left; font-size: 9px; padding: 5px 6px; border-bottom: 1px solid #d7dbe3; }
.grid td { font-size: 9px; padding: 4px 6px; border-bottom: 1px solid #eceef2; }
.facts td { padding: 3px 12px 3px 0; font-size: 11px; }
.facts .key { color: #6b7280; }
"""


def render(report, built: dict, *, school_label: str, generated_at: str) -> bytes:
    out = io.BytesIO()
    result = pisa.CreatePDF(document(report, built, school_label=school_label, generated_at=generated_at), dest=out,
                            encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render the {report.TITLE} report")

    return out.getvalue()


def file_name(slug: str, built: dict) -> str:
    start, end = built["range"]["from"], built["range"]["to"]
    return f"{slug}-group-{start}-to-{end}.pdf" if built.get("group") else f"{slug}-{start}-to-{end}.pdf"


def document(report, built: dict, *, school_label: str, generated_at: str) -> str:
    """The report as HTML. Separate from render() so a test can read it."""
    is_group = built.get("group", False)
    compared = "comparison" in built
    period = built["range"]
    working_days = period.get("working_days")

    headings = (["School"] if is_group else []) + report.headings()
    rows = report.csv_rows(built)
    if is_group:
        rows = [[row["school_name"], *line] for row, line in zip(built["rows"], rows)]
    if compared:
        headings += comparison.headings(report)
        rows = [[*line, *comparison.cells(report, row)] for row, line in zip(built["rows"], rows)]

    head_cells = "".join(f"<th>{e(heading)}</th>" for heading in headings)
    body = "".join("<tr>" + "".join(f"<td>{cell(value)}</td>" for value in line) + "</tr>" for line in rows)
    if not rows:
        body = f'<tr><td colspan="{len(headings)}" class="muted">Nothing to report for this period.</td></tr>'

    days = "" if working_days is None else f"{text(working_days)} working days"

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>{STYLESHEET}{REPORT_STYLES}</style></head>
<body>
<div class="sheet">
    <table class="head"><tr>
        <td><div class="brand">{e(school_label)}</div><div class="muted">{e(report.TITLE)}</div></td>
        <td class="right"><div>{e(period["from"])} to {e(period["to"])}</div><div class="muted">{days}</div></td>
    </tr></table>

    <h1>Summary</h1>
    {totals_table(built)}

    <h1>Detail</h1>
    <table class="grid"><tr>{head_cells}</tr>{body}</table>

    <div class="note muted">
        {e(getattr(report, "PDF_NOTE", DEFAULT_NOTE))} Generated {e(generated_at)}.
    </div>
</div>
</body>
</html>"""


def totals_table(built: dict) -> str:
    totals = built["totals"]
    previous = built.get("comparison", {}).get("totals")
    lines = []

    for key, value in totals.items():
        if key == "by_currency":
            lines += currency_lines(value, None if previous is None else previous.get(key))
            continue

        before = "" if previous is None else f'<td class="muted">previous: {figure(key, previous.get(key))}</td>'
        lines.append(f'<tr><td class="key">{e(humanise(key))}</td><td><b>{figure(key, value)}</b></td>{before}</tr>')

    if previous is not None:
        period = built["comparison"]["range"]
        lines.append(f'<tr><td class="key">Previous period</td><td>{e(period["from"])} to {e(period["to"])}</td></tr>')

    return f'<table class="facts">{"".join(lines)}</table>'


def currency_lines(entries: list[dict], previous: list[dict] | None) -> list[str]:
    """Payroll's money, one line per currency - never added across them."""
    before = {entry["currency_code"]: entry for entry in previous or []}
    lines = []

    for entry in entries:
        code = entry["currency_code"]
        earlier = before.get(code)
        was = "" if previous is None else (
            f'<td class="muted">previous: {cash(earlier["net"], code) if earlier else "-"}</td>'
        )
        lines.append(
            f'<tr><td class="key">Net pay ({e(code)})</td><td><b>{cash(entry["net"], code)}</b>'
            f' <span class="muted">gross {cash(entry["gross"], code)}, unpaid {cash(entry["unpaid"], code)}</span>'
            f'</td>{was}</tr>'
        )

    return lines


def figure(key: str, value) -> str:
    if value is None:
        return "-"
    if isinstance(value, list):
        return text(", ".join(str(item) for item in value)) or "-"
    if key.endswith(("rate", "completion")):
        return f"{text(value)}%"
    return text(value)


def cell(value) -> str:
    return "-" if value is None or value == "" else text(value)


def text(value) -> str:
    """Escaped, keeping a zero - the receipt's e() reads 0 as nothing."""
    return html.escape(str(value))


def cash(amount: str, code: str) -> str:
    return e(money.formatted(Decimal(amount), code))


def humanise(key: str) -> str:
    return key.replace("_", " ").capitalize()
