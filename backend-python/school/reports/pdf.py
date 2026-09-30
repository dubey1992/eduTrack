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

from .. import dates, money
from ..receipts import STYLESHEET, e
from . import comparison

DEFAULT_NOTE = "Every rate is out of the days the school actually ran: weekends and the school's holidays are not counted."

REPORT_STYLES = """
@page {
    size: a4 landscape;
    margin: 14mm 12mm 16mm 12mm;
    @frame footer { -pdf-frame-content: page-footer; bottom: 7mm; height: 7mm; margin-left: 12mm; margin-right: 12mm; }
}
.sheet { padding: 0; }
.grid { margin-top: 10px; border: 1px solid #d7dbe3; }
.grid th { background: #f3f4f6; text-align: left; font-size: 9px; padding: 5px 6px; border-bottom: 1px solid #d7dbe3; }
.grid td { font-size: 9px; padding: 4px 6px; border-bottom: 1px solid #eceef2; }
.facts td { padding: 3px 12px 3px 0; font-size: 11px; }
.facts .key { color: #6b7280; width: 160px; }
.grid th.num, .grid td.num { text-align: right; }
.strip { margin-top: 10px; border-top: 1px solid #eceef2; border-bottom: 1px solid #eceef2; }
.strip td { padding: 5px 12px 5px 0; font-size: 10px; }
.strip .key { color: #6b7280; width: 90px; }
.foot { font-size: 9px; color: #6b7280; }
.foot .right { text-align: right; }
"""


def render(report, built: dict, *, school_label: str, generated_at: str, filters: list | None = None) -> bytes:
    out = io.BytesIO()
    page = document(report, built, school_label=school_label, generated_at=generated_at, filters=filters)
    result = pisa.CreatePDF(page, dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render the {report.TITLE} report")

    return out.getvalue()


def file_name(slug: str, built: dict) -> str:
    start, end = built["range"]["from"], built["range"]["to"]
    return f"{slug}-group-{start}-to-{end}.pdf" if built.get("group") else f"{slug}-{start}-to-{end}.pdf"


def document(report, built: dict, *, school_label: str, generated_at: str, filters: list | None = None) -> str:
    """The report as HTML. Separate from render() so a test can read it.

    `filters` is what was asked for, already turned into labels by the view
    - the one thing a printed report cannot leave out. A sheet narrowed to
      one class, or to the students under 40%, looks exactly like the whole
      school's on paper, and somebody will read it as the whole school's.
    """
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

    numeric = numeric_columns(rows, len(headings))
    head_cells = "".join(
        f"<th{align(numeric[index])}>{e(heading)}</th>" for index, heading in enumerate(headings)
    )
    body = "".join(
        "<tr>"
        + "".join(f"<td{align(numeric[index])}>{cell(value)}</td>" for index, value in enumerate(line))
        + "</tr>"
        for line in rows
    )
    if not rows:
        body = f'<tr><td colspan="{len(headings)}" class="muted">Nothing to report for this period.</td></tr>'

    days = "" if working_days is None else f"{text(working_days)} working days"

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>{STYLESHEET}{REPORT_STYLES}</style></head>
<body>
<div id="page-footer">
    <table class="foot"><tr>
        <td>{e(school_label)} &#183; {e(report.TITLE)}</td>
        <td class="right">Page <pdf:pagenumber> of <pdf:pagecount></td>
    </tr></table>
</div>
<div class="sheet">
    <table class="head"><tr>
        <td><div class="brand">{e(school_label)}</div><div class="muted">{e(report.TITLE)}</div></td>
        <td class="right"><div>{e(dates.range_label_iso(period["from"], period["to"]))}</div><div class="muted">{days}</div></td>
    </tr></table>

    {sheet_facts(built, rows, filters, generated_at)}

    <h1>Summary</h1>
    {totals_table(built)}

    <h1>Detail</h1>
    <table class="grid"><thead><tr>{head_cells}</tr></thead><tbody>{body}</tbody></table>

    <div class="note muted">
        {e(getattr(report, "PDF_NOTE", DEFAULT_NOTE))}
    </div>
</div>
</body>
</html>"""


def align(is_numeric: bool) -> str:
    return ' class="num"' if is_numeric else ""


def numeric_columns(rows: list, width: int) -> list[bool]:
    """Which columns hold figures rather than words.

    Decided from the rows rather than declared by each report, so a new
    column lines up without anybody remembering to say so. A column with
    nothing in it is not numeric - there is nothing to line up.
    """
    numeric = []

    for index in range(width):
        values = [line[index] for line in rows if index < len(line) and line[index] not in (None, "")]
        numeric.append(bool(values) and all(isinstance(value, (int, float, Decimal)) for value in values))

    return numeric


def sheet_facts(built: dict, rows: list, filters: list | None, generated_at: str) -> str:
    """What this particular sheet is, above the figures.

    Every line here answers a question somebody holding the paper will ask:
    what was it narrowed to, how many lines should there be, and when was
    it run. Without the first, a filtered report is indistinguishable from
    the whole school's.
    """
    lines = [("Filters", ", ".join(f"{label}: {value}" for label, value in (filters or [])) or "None")]

    if built.get("group"):
        branches = built.get("branches") or []
        lines.append(("Branches", ", ".join(branch["school_name"] for branch in branches) or "None"))

    lines.append(("Rows", str(len(rows))))
    lines.append(("Generated", generated_at))

    cells = "".join(f'<tr><td class="key">{e(label)}</td><td>{e(value)}</td></tr>' for label, value in lines)

    return f'<table class="strip">{cells}</table>'


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
        lines.append(
            f'<tr><td class="key">Previous period</td>'
            f'<td>{e(dates.range_label_iso(period["from"], period["to"]))}</td></tr>'
        )

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
