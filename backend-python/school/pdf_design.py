"""The one look every PDF the platform prints shares (docs/pdf-design.md).

The fee receipt (fees/receipt_pdf.py) set the standard: an A4 page with a
blue band carrying the school's logo, name and contact lines, the document's
title and number on the right, labelled facts side by side, striped tables, a
totals panel with the amount in words, a stamp for a void document, and a
footer saying when it was issued in the school's own timezone. This module is
that look, taken out of the receipt so the payslip, the progress report, the
reports and the Super Admin's payment receipt can wear it too - plus what
those need and a receipt did not: headline figure tiles, signature lines,
landscape pages for wide tables, and a running footer with "Page X of Y" on
every page.

The engine is xhtml2pdf, because shared hosting has no cairo or pango (which
rules out WeasyPrint): tables and simple CSS only - no flexbox, no grid, no
rotation, no web fonts. Spacing is done with spacer rows because xhtml2pdf
ignores margins on most elements.

Two rules every piece here keeps:

- **Never print an empty value.** A fact with no value is left out, a logo
  that cannot be fetched is left out, a contact line with nothing on it is
  left out - a document never reads "None" or shows an empty label.
- **Everything typed by a person is escaped** (school names, notes,
  reasons): an ampersand or an angle bracket must print, never become markup.

And one the engine imposes: **never give two rules the same specificity if
they can match the same element** - repeating `.items td` in a document's
own styles, say. xhtml2pdf cannot rank such a pair and silently prints the
cell with no styles at all. A document narrows a shared rule with a more
specific selector of its own (`table.compact td`), and its tests assert
`style_errors(html) == 0`.

And: **no colspan in a table that sets its column widths** - xhtml2pdf then
gets every width wrong. A totals line goes under it as a one-row table of its
own (`total_row`).
"""

from __future__ import annotations

import base64
import io
import logging
import urllib.request

from xhtml2pdf import pisa

from .receipts import e

logger = logging.getLogger(__name__)

BRAND = "#2563EB"
BRAND_DARK = "#1E3A8A"
BRAND_SOFT = "#EFF6FF"
BRAND_LINE = "#C7D2FE"
INK = "#1F2937"
MUTED = "#6B7280"
RULE = "#E5E7EB"

LOGO_TIMEOUT_SECONDS = 3
LOGO_MAX_BYTES = 2 * 1024 * 1024
LOGO_TYPES = ("image/png", "image/jpeg", "image/jpg", "image/gif")

# Tones a stamp, a tile or a row can take: (text, background, border).
TONES = {
    "danger": ("#B91C1C", "#FEF2F2", "#B91C1C"),
    "success": ("#065F46", "#ECFDF5", "#059669"),
    "warning": ("#9A3412", "#FFF7ED", "#EA580C"),
    "info": (BRAND_DARK, BRAND_SOFT, BRAND),
    "neutral": ("#374151", "#F9FAFB", "#9CA3AF"),
}


def page_rules(landscape: bool = False) -> str:
    """The page size and margins, with a frame at the bottom of every page
    for the running footer (`running_footer`)."""
    size = "a4 landscape" if landscape else "a4 portrait"

    return f"""
@page {{
    size: {size};
    margin: 1.4cm 1.5cm 1.9cm 1.5cm;
    @frame footer {{ -pdf-frame-content: page-footer; bottom: 0.7cm; height: 0.8cm;
        margin-left: 1.5cm; margin-right: 1.5cm; }}
}}"""


STYLESHEET = f"""
body {{ font-family: Helvetica, sans-serif; font-size: 10pt; color: {INK}; }}
table {{ width: 100%; border-collapse: collapse; }}
td, th {{ vertical-align: top; }}

.band td {{ background-color: {BRAND}; color: #ffffff; }}
.band .logo {{ width: 70px; padding: 14px 0 14px 16px; vertical-align: middle; }}
.band .school {{ padding: 14px 16px; vertical-align: middle; }}
.band .title {{ width: 230px; padding: 14px 16px; text-align: right; vertical-align: middle; }}
.school-name {{ font-size: 17pt; font-weight: bold; }}
.school-line {{ font-size: 8.5pt; color: #dbeafe; line-height: 1.5; padding-top: 4px; }}
.doc-title {{ font-size: 14pt; font-weight: bold; }}
.doc-number {{ font-size: 10.5pt; padding-top: 4px; }}
.doc-sub {{ font-size: 9pt; color: #dbeafe; padding-top: 2px; }}

.stamp td {{ border: 3px solid #b91c1c; background-color: #fef2f2; color: #b91c1c; padding: 10px 14px; }}
.stamp-word {{ font-size: 26pt; font-weight: bold; letter-spacing: 6px; }}
.stamp-line {{ font-size: 9.5pt; line-height: 1.5; }}

.label {{ font-size: 7.5pt; color: {MUTED}; text-transform: uppercase; letter-spacing: 1px; }}
.section-title {{ font-size: 8pt; font-weight: bold; color: {MUTED}; letter-spacing: 1px;
    padding: 0 0 5px 0; border-bottom: 1px solid {RULE}; }}
.facts td {{ padding: 2px 0; font-size: 9.5pt; }}
.facts .key {{ width: 105px; color: {MUTED}; }}
.facts .value {{ font-weight: bold; color: #111827; }}

.items th {{ background-color: #e0e7ff; color: {BRAND_DARK}; font-size: 8.5pt; text-align: left;
    padding: 7px 8px; border-bottom: 1px solid {BRAND_LINE}; }}
.items td {{ padding: 5px 8px; font-size: 9.5pt; border-bottom: 1px solid {RULE}; }}
.items .zebra td {{ background-color: #f8fafc; }}
.items .num {{ text-align: right; }}
.items .idx {{ width: 24px; color: {MUTED}; }}
.items .total td {{ background-color: {BRAND_SOFT}; font-weight: bold; color: {BRAND_DARK};
    border-top: 1px solid {BRAND_LINE}; }}

.totals td {{ background-color: {BRAND_SOFT}; padding: 6px 14px; }}
.totals .big-label {{ font-size: 11pt; font-weight: bold; color: {BRAND_DARK}; padding-top: 10px;
    vertical-align: middle; }}
.totals .big-value {{ font-size: 16pt; font-weight: bold; color: {BRAND_DARK}; text-align: right; padding-top: 10px; }}
.totals .words {{ font-size: 9pt; font-style: italic; color: {INK}; padding-top: 0; padding-bottom: 8px; }}

.balances td {{ padding: 4px 12px; font-size: 9.5pt; border-bottom: 1px solid {RULE}; }}
.balances .value {{ text-align: right; font-weight: bold; }}
.balances .after td {{ background-color: #fff7ed; color: #9a3412; font-weight: bold; }}
.balances .settled td {{ background-color: #ecfdf5; color: #065f46; font-weight: bold; }}

.tiles td.tile {{ padding: 9px 12px; border: 1px solid {RULE}; }}
.tiles .tile-label {{ font-size: 7.5pt; color: {MUTED}; text-transform: uppercase; letter-spacing: 1px; }}
.tiles .tile-value {{ font-size: 15pt; font-weight: bold; padding-top: 3px; }}
.tiles .tile-hint {{ font-size: 7.5pt; color: {MUTED}; padding-top: 2px; }}

.signs td.sign {{ padding: 34px 10px 0 10px; text-align: center; font-size: 8.5pt; color: {MUTED}; }}
.signs .sign-line {{ border-top: 1px solid #9ca3af; padding-top: 4px; }}

.note {{ font-size: 9.5pt; padding: 8px 12px; border-left: 3px solid {BRAND}; background-color: #f8fafc; }}
.footer td {{ font-size: 8pt; color: {MUTED}; padding-top: 3px; text-align: center; }}
.rule {{ border-top: 1px solid {RULE}; }}
.page-foot td {{ font-size: 7.5pt; color: #9ca3af; }}
.page-foot .right {{ text-align: right; }}
.muted {{ color: {MUTED}; }}
"""


# -- small pieces ---------------------------------------------------------------


def joined(*parts, separator: str = ", ") -> str:
    """The parts that have a value, joined."""
    return separator.join(str(part).strip() for part in parts if part is not None and str(part).strip())


def spacer(height: int) -> str:
    """Vertical space: xhtml2pdf ignores most margins, so an empty row it is."""
    return f'<table><tr><td style="height: {height}px; font-size: 1pt;">&nbsp;</td></tr></table>'


def fact(key: str, value) -> str:
    """One labelled line, or nothing at all when there is no value."""
    if value is None or str(value).strip() == "":
        return ""

    return f'<tr><td class="key">{e(key)}</td><td class="value">{e(value)}</td></tr>'


def facts(pairs) -> str:
    """A block of labelled lines - the empty ones left out."""
    return f'<table class="facts">{"".join(fact(key, value) for key, value in pairs)}</table>'


def section(title: str, top: int = 16) -> str:
    """A small grey heading with a rule under it, and a little room after."""
    # Kept with what follows it: a heading never ends a page on its own.
    return (
        f'{spacer(top)}<div class="section-title" style="-pdf-keep-with-next: true;">{e(title.upper())}</div>'
        f'<div style="-pdf-keep-with-next: true;">{spacer(6)}</div>'
    )


def side_by_side(left: str, right: str, left_title: str | None = None, right_title: str | None = None) -> str:
    """Two blocks in two columns, each under its own heading."""
    def block(title, body):
        heading = f'<div class="section-title">{e(title.upper())}</div>' if title else ""
        return f"{heading}{body}"

    return f"""
    <table><tr>
        <td style="width: 48%">{block(left_title, left)}</td>
        <td style="width: 4%"></td>
        <td style="width: 48%">{block(right_title, right)}</td>
    </tr></table>"""


# -- the header band ------------------------------------------------------------


def logo_data_uri(url: str | None) -> str | None:
    """A logo, fetched and inlined - or None, so a logo that is missing, slow,
    too big or not an image costs the document its logo and nothing else.
    Logged, never raised."""
    if not url or not url.lower().startswith(("http://", "https://")):
        return None

    try:
        request = urllib.request.Request(url, headers={"User-Agent": "School365ai documents"})

        with urllib.request.urlopen(request, timeout=LOGO_TIMEOUT_SECONDS) as response:  # noqa: S310 - http(s) only
            kind = (response.headers.get_content_type() or "").lower()
            body = response.read(LOGO_MAX_BYTES + 1)
    except Exception as error:  # noqa: BLE001 - any failure means "no logo", by design
        logger.warning("PDF: could not fetch the logo %s (%s)", url, error)
        return None

    if kind not in LOGO_TYPES or len(body) > LOGO_MAX_BYTES or not body:
        logger.warning("PDF: the logo %s is not a usable image (%s, %s bytes)", url, kind, len(body))
        return None

    return f"data:{kind};base64,{base64.b64encode(body).decode('ascii')}"


def school_lines(school) -> list[str]:
    """A school's contact lines for the band: address, phone and email, and
    its registration number - each only when it has one."""
    return [
        line
        for line in (
            joined(school.address, school.city, school.state, school.postal_code, school.country),
            joined(f"Phone {school.phone}" if school.phone else None, school.email),
            f"Reg. no. {school.registration_number}" if school.registration_number else "",
        )
        if line
    ]


def band(name: str, lines: list[str], title: str, number: str | None = None, subtitle: str | None = None,
         logo_url: str | None = None) -> str:
    """The blue band: a logo when there is one, the issuer's name and contact
    lines, and on the right the document's title, its number and a line under
    it."""
    logo = logo_data_uri(logo_url)
    logo_cell = f'<td class="logo"><img src="{logo}" width="60" height="60"></td>' if logo else ""
    shown = "<br/>".join(e(line) for line in lines if line)
    contact = f'<div class="school-line">{shown}</div>' if shown else ""
    number_line = f'<div class="doc-number">{e(number)}</div>' if number else ""
    sub_line = f'<div class="doc-sub">{e(subtitle)}</div>' if subtitle else ""

    return f"""
    <table class="band"><tr>
        {logo_cell}
        <td class="school"><div class="school-name">{e(name)}</div>{contact}</td>
        <td class="title"><div class="doc-title">{e(title)}</div>{number_line}{sub_line}</td>
    </tr></table>"""


def school_band(school, title: str, number: str | None = None, subtitle: str | None = None) -> str:
    """The band for a document a school issues."""
    return band(school.name, school_lines(school), title, number, subtitle, logo_url=school.logo_url)


# -- blocks ---------------------------------------------------------------------


def stamp(word: str, lines: list[str], tone: str = "danger") -> str:
    """A boxed word across the page - CANCELLED, DRAFT - with what it means
    under it."""
    text, background, border = TONES[tone]
    body = "<br/>".join(e(line) for line in lines if line)

    return f"""
    {spacer(14)}
    <table class="stamp"><tr><td style="border-color: {border}; background-color: {background}; color: {text};">
        <div class="stamp-word">{e(word)}</div><div class="stamp-line">{body}</div>
    </td></tr></table>"""


def tiles(items: list[dict], per_row: int = 4) -> str:
    """Headline figures in boxes: each {label, value, hint?, tone?}. Rows of
    `per_row`, the last one padded so every box keeps its width."""
    if not items:
        return ""

    width = f"{100 // per_row}%"
    rows = []

    for start in range(0, len(items), per_row):
        cells = []

        for item in items[start:start + per_row]:
            text, background, _ = TONES[item.get("tone") or "neutral"]
            hint = f'<div class="tile-hint">{e(item["hint"])}</div>' if item.get("hint") else ""
            cells.append(
                f'<td class="tile" width="{width}" style="background-color: {background};">'
                f'<div class="tile-label">{e(item["label"])}</div>'
                f'<div class="tile-value" style="color: {text};">{e(item["value"])}</div>{hint}</td>'
            )

        cells += [f'<td width="{width}"></td>'] * (per_row - len(cells))
        rows.append(f"<tr>{''.join(cells)}</tr>")

    return f'<table class="tiles">{"".join(rows)}</table>'


def table(headings: list[tuple[str, str | None, bool]], rows: list[list[str]], total: list[str] | None = None,
          empty: str = "Nothing to show.") -> str:
    """A striped table. `headings` are (text, width or None, numeric);
    `rows` cells are already-escaped HTML; `total` is an optional last row.
    The heading repeats on every page the table runs over."""
    if not rows:
        return f'<div class="note">{e(empty)}</div>'

    num = ' class="num"'

    def heading(text, width, is_numeric):
        sized = f' width="{width}"' if width else ""
        return f"<th{num if is_numeric else ''}{sized}>{e(text)}</th>"

    head = "".join(heading(*column) for column in headings)
    numeric = [is_numeric for _, _, is_numeric in headings]

    def row(cells, css=""):
        return f'<tr class="{css}">' + "".join(
            f"<td{num if numeric[index] else ''}>{cell}</td>" for index, cell in enumerate(cells)
        ) + "</tr>"

    body = "".join(row(cells, "zebra" if index % 2 else "") for index, cells in enumerate(rows))
    foot = row(total, "total") if total else ""

    return f'<table class="items" repeat="1"><tr>{head}</tr>{body}{foot}</table>'


def total_row(cells: list[tuple[str, str, bool]], table_class: str = "items") -> str:
    """A totals line under a table whose columns have set widths: (html,
    width, numeric) - each cell as wide as the columns above it that it sums.
    Its own one-row table, never a row with a colspan inside the table above:
    xhtml2pdf gets the widths of every column wrong when a table that sets
    them also has a spanning cell, and squeezes the last one."""
    num = ' class="num"'
    row = "".join(f'<td{num if numeric else ""} width="{width}">{html}</td>' for html, width, numeric in cells)

    return f'<table class="{table_class}"><tr class="total">{row}</tr></table>'


def totals_panel(label: str, value: str, words: str | None = None) -> str:
    """The big figure - total received, net pay - with it in words."""
    words_row = f'<tr><td class="words" colspan="2">{e(words)}</td></tr>' if words else ""

    return f"""
    <table class="totals">
        <tr><td class="big-label">{e(label)}</td><td class="big-value">{e(value)}</td></tr>
        {words_row}
    </table>"""


def signatures(names: list[str]) -> str:
    """Lines to sign on, each with whose signature it is."""
    if not names:
        return ""

    width = f"{100 // len(names)}%"
    cells = "".join(
        f'<td class="sign" width="{width}"><div class="sign-line">{e(name)}</div></td>' for name in names
    )

    return f'<table class="signs"><tr>{cells}</tr></table>'


def closing(lines: list[str]) -> str:
    """The centred lines at the end of the document."""
    rows = [f'<tr><td class="rule">{e(lines[0])}</td></tr>'] if lines else []
    rows += [f"<tr><td>{e(line)}</td></tr>" for line in lines[1:]]

    return f'{spacer(22)}<table class="footer">{"".join(rows)}</table>'


def running_footer(left: str) -> str:
    """What every page carries at its foot: whose document it is, and
    "Page X of Y"."""
    return f"""
<div id="page-footer">
    <table class="page-foot"><tr>
        <td>{e(left)}</td>
        <td class="right">Page <pdf:pagenumber> of <pdf:pagecount></td>
    </tr></table>
</div>"""


# -- the whole page -------------------------------------------------------------


def page(title: str, body: str, *, footer: str, landscape: bool = False, extra_styles: str = "") -> str:
    """A complete document: the page rules, the shared styles and any of its
    own, the running footer and the body."""
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{e(title)}</title>
<style>{page_rules(landscape)}{STYLESHEET}{extra_styles}</style>
</head>
<body>
{running_footer(footer)}
{body}
</body>
</html>"""


def style_errors(html: str) -> int:
    """How many times xhtml2pdf gave up on a cell's styles while laying the
    document out. It does so silently - logged at DEBUG, the cell printed
    unstyled - when two rules of the same specificity match one element (a
    bug in its cascade: it cannot rank them). Kept here so every document's
    tests can assert it is nought."""
    class Counter(logging.Handler):
        count = 0

        def emit(self, record):
            if "not supported between instances" in record.getMessage():
                Counter.count += 1

    handler = Counter(level=logging.DEBUG)
    parser = logging.getLogger("xhtml2pdf")
    level = parser.level
    parser.addHandler(handler)
    parser.setLevel(logging.DEBUG)

    try:
        pisa.CreatePDF(html, dest=io.BytesIO(), encoding="utf-8")
    finally:
        parser.removeHandler(handler)
        parser.setLevel(level)

    return Counter.count


def render(html: str, name: str) -> bytes:
    """The PDF, ready to download or attach to an email."""
    out = io.BytesIO()
    result = pisa.CreatePDF(html, dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render {name}")

    return out.getvalue()
