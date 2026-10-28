"""Any report as a printable PDF (Phase 20; docs/pdf-design.md, phase 4).

The same figures as the screen and the CSV - the rows are the report's own
csv_rows(), so the three can never disagree - laid out for a printer in the
platform's shared look (school/pdf_design.py): landscape A4; the school's
blue band with the report's name, its period and working days; what this
sheet is (filters, branches, rows, when it was run) beside the period it was
compared with; the totals as headline tiles, each with the previous period's
figure under it when a comparison was asked for; then every row, the heading
repeated on each page; and how the figures are worked out.

A group report (every branch at once) carries the group's label in the band
instead of one school's address.
"""

from __future__ import annotations

import html
from decimal import Decimal

from .. import dates, money, pdf_design
from . import comparison

DEFAULT_NOTE = "Every rate is out of the days the school actually ran: its days off and its holidays are not counted."

REPORT_STYLES = """
table.report th { font-size: 7.5pt; padding: 6px 5px; }
table.report td { font-size: 8pt; padding: 4px 5px; }
table.band td.school { padding: 10px 16px; }
table.band td.title { width: 420px; padding: 10px 16px; }
"""


def render(report, built: dict, *, school_label: str, generated_at: str, filters: list | None = None,
           school=None) -> bytes:
    page = document(report, built, school_label=school_label, generated_at=generated_at, filters=filters,
                    school=school)

    return pdf_design.render(page, f"the {report.TITLE} report")


def file_name(slug: str, built: dict) -> str:
    start, end = built["range"]["from"], built["range"]["to"]
    return f"{slug}-group-{start}-to-{end}.pdf" if built.get("group") else f"{slug}-{start}-to-{end}.pdf"


def document(report, built: dict, *, school_label: str, generated_at: str, filters: list | None = None,
             school=None) -> str:
    """The report as HTML. Separate from render() so a test can read it.

    `filters` is what was asked for, already turned into labels by the view
    - the one thing a printed report cannot leave out. A sheet narrowed to
      one class, or to the students under 40%, looks exactly like the whole
      school's on paper, and somebody will read it as the whole school's.
    `school` is the one school the report is about, for its logo and
    contact lines; a group report has none.
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
    widths = column_widths(headings, rows)
    table = pdf_design.table(
        [(heading, widths[index], numeric[index]) for index, heading in enumerate(headings)],
        [[cell(value) for value in line] for line in rows],
        empty="Nothing to report for this period.",
        table_class="items report",
    )

    # The fee reports count money, not days the school ran.
    shows_days = getattr(report, "SHOWS_WORKING_DAYS", True)
    days = None if working_days is None or not shows_days else f"{text(working_days)} working days"
    span = dates.range_label_iso(period["from"], period["to"])

    if school is not None and not is_group:
        band = pdf_design.school_band(school, report.TITLE.upper(), span, days)
    else:
        band = pdf_design.band(school_label, [], report.TITLE.upper(), span, days)

    # When it was run is in the facts above; the period is in the band.
    closing = [getattr(report, "PDF_NOTE", DEFAULT_NOTE), "Powered by School365ai"]

    body = f"""
    {band}
    {pdf_design.spacer(14)}
    {pdf_design.side_by_side(sheet_facts(built, rows, filters), run_facts(built, generated_at),
                             "This sheet", "Run")}

    {pdf_design.section("Summary")}
    {summary(built, report)}

    {pdf_design.section("Detail", keep=False)}
    {table}
    {pdf_design.closing([line for line in closing if line])}
"""

    return pdf_design.page(
        f"{report.TITLE} - {school_label}", body, footer=f"{school_label} - {report.TITLE} - {span}",
        landscape=True, extra_styles=REPORT_STYLES,
    )


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


def column_widths(headings: list, rows: list) -> list[str]:
    """Each column's share of the page, from what it holds: its longest
    value, or the longest word of its heading (a heading wraps between
    words, a value like a receipt number cannot). Left to itself xhtml2pdf
    gives every column the same width, and a long receipt number runs into
    the column beside it."""
    def longest_word(value) -> int:
        return max((len(word) for word in str(value).split()), default=1)

    sizes = []

    for index, heading in enumerate(headings):
        values = [len(str(line[index])) for line in rows[:500] if index < len(line) and line[index] is not None]
        size = max([longest_word(heading), *values, 3])
        # Long free text (a reason, a note) wraps; it should not starve the rest.
        sizes.append(min(size, 28))

    total = sum(sizes) or 1

    return [f"{size / total * 100:.2f}%" for size in sizes]


def sheet_facts(built: dict, rows: list, filters: list | None) -> str:
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

    return pdf_design.facts(lines)


def run_facts(built: dict, generated_at: str) -> str:
    """When the sheet was run, and the period its figures were set beside.
    The period itself and its working days are in the band."""
    lines = [("Generated", generated_at)]

    if "comparison" in built:
        earlier = built["comparison"]["range"]
        lines.append(("Compared with", dates.range_label_iso(earlier["from"], earlier["to"])))

    return pdf_design.facts(lines)


def summary(built: dict, report=None) -> str:
    """The totals as headline tiles, the previous period's figure under each
    when a comparison was asked for."""
    totals = built["totals"]
    previous = built.get("comparison", {}).get("totals")
    items = []

    # A report whose totals are lists - money per currency - says how to
    # print them (the fee reports): (label, value, previous or None) each.
    if report is not None and hasattr(report, "pdf_totals"):
        for label, value, before in report.pdf_totals(totals, previous):
            items.append(tile(label, value, None if previous is None or before is None else before))

        totals = {}

    for key, value in totals.items():
        if key == "by_currency":
            items += currency_tiles(value, None if previous is None else previous.get(key))
            continue

        before = None if previous is None else figure(key, previous.get(key), escape=False)
        items.append(tile(humanise(key), figure(key, value, escape=False), before, key=key))

    if not items:
        return '<div class="note">No totals for this period.</div>'

    return pdf_design.tiles(items, per_row=5)


def tile(label: str, value, before=None, key: str = "") -> dict:
    """One headline figure. A rate is blue; the rest stay quiet."""
    return {
        "label": label,
        "value": value,
        "hint": None if before is None else f"previous: {before}",
        "tone": "info" if key.endswith(("rate", "completion")) else "neutral",
    }


def currency_tiles(entries: list[dict], previous: list[dict] | None) -> list[dict]:
    """Payroll's money, one tile per currency - never added across them."""
    before = {entry["currency_code"]: entry for entry in previous or []}
    tiles = []

    for entry in entries:
        code = entry["currency_code"]
        earlier = before.get(code)
        hint = f"gross {cash(entry['gross'], code)}, unpaid {cash(entry['unpaid'], code)}"
        if previous is not None:
            hint += f" - previous: {cash(earlier['net'], code) if earlier else '-'}"
        tiles.append({"label": f"Net pay ({code})", "value": cash(entry["net"], code), "hint": hint,
                      "tone": "success"})

    return tiles


def figure(key: str, value, escape: bool = True) -> str:
    """A total as a person reads it: a rate with its % sign, a list joined,
    nothing as a dash. Escaped unless it goes into a tile, which escapes."""
    show = text if escape else str

    if value is None:
        return "-"
    if isinstance(value, list):
        return show(", ".join(str(item) for item in value)) or "-"
    if key.endswith(("rate", "completion")):
        return f"{show(value)}%"
    return show(value)


def cell(value) -> str:
    return "-" if value is None or value == "" else text(value)


def text(value) -> str:
    """Escaped, keeping a zero - the receipt's e() reads 0 as nothing."""
    return html.escape(str(value))


def cash(amount: str, code: str) -> str:
    return money.formatted(Decimal(amount), code)


def humanise(key: str) -> str:
    return key.replace("_", " ").capitalize()

