"""The classic printed report card (docs/document-styles.md, decided
2026-11-17): the layout of a school's printed marksheet, for schools that
choose it under Module Settings -> Class Tests -> Report card layout.

- **Header.** A light-blue band: the school's logo, its name, address and phone, "Report Card", then the academic session.
- **Student block.** Admission no, name, father's and mother's names where a Family-app parent link gives them (else the guardian), address, roll no, class and section as they were that year, and a box for the photo.
- **Marks.** One table, every term side by side. Under each term come its tests (titled as the teachers named them, with the marks each is out of), the term's marks and grade, and on a grade-point scale the points. A grades-only scale prints each term's grade alone.
- **Totals.** Each term's marks and percentage (or GPA, or grade) and the attendance; then the year's total, percentage, grade, rank when the school prints one, and the result.
- **Below the totals.** The class teacher's remark, the school's word to parents, its instructions and the grading key, and the class teacher's and principal's signatures.

Every figure is report_card.py's. This file only lays them out.
"""

from __future__ import annotations

import decimal
from types import SimpleNamespace

from . import pdf_design, report_card
from .clock import SchoolClock
from .enums import GradeScaleKind
from .models import AcademicTerm, StudentEnrollment, StudentTermRemark
from .parent_names import parent_names
from .performance import StudentPerformance
from .receipts import e

INK = "#13293d"
HEAD = "#a8c9ee"
HEAD_INK = "#163758"
SUB = "#cfe2f6"
LIGHT = "#eef3f9"
LINE = "#596573"


def styles(landscape: bool) -> str:
    size = "a4 landscape" if landscape else "a4 portrait"

    return f"""
@page {{ size: {size}; margin: 1.0cm 1.1cm 1.0cm 1.1cm; }}
body {{ font-family: Helvetica, sans-serif; font-size: 8.5pt; color: {INK}; }}
table {{ width: 100%; border-collapse: collapse; }}
td, th {{ vertical-align: top; }}

.head td {{ background-color: {HEAD}; }}
.head .logo-cell {{ width: 70px; padding: 6px 0 6px 10px; vertical-align: middle; }}
.head .middle {{ text-align: center; padding: 6px 70px 6px 0; vertical-align: middle; }}
.school {{ font-size: 17pt; font-weight: bold; color: {HEAD_INK}; }}
.sub {{ font-size: 8.5pt; font-weight: bold; color: #234b72; padding-top: 1px; }}
.doc {{ font-size: 13pt; font-weight: bold; color: #183f6c; padding-top: 3px; }}
.session {{ text-align: center; font-weight: bold; font-size: 9.5pt; padding: 6px 0; }}

.meta td {{ padding: 2px 0; font-size: 8.5pt; }}
.meta .k {{ width: 102px; font-weight: bold; }}
.meta .colon {{ width: 8px; font-weight: bold; }}
.photo td {{ border: 1px solid #7891a8; background-color: #e7eff8; color: #54708a; text-align: center;
    vertical-align: middle; font-size: 7pt; font-weight: bold; height: 82px; }}

.marks th {{ border: 1px solid {LINE}; background-color: {LIGHT}; font-size: 7pt; padding: 4px 2px;
    text-align: center; vertical-align: middle; }}
.marks td {{ border: 1px solid {LINE}; font-size: 8pt; padding: 4px 2px; text-align: center; }}
.marks .term {{ background-color: {SUB}; font-size: 8pt; }}
.marks .subject {{ text-align: left; padding-left: 5px; font-weight: bold; }}
.marks .strong {{ font-weight: bold; }}
.marks .fail {{ font-weight: bold; color: #b91c1c; }}

.mini td {{ border: 1px solid {LINE}; padding: 5px 7px; font-weight: bold; font-size: 8.5pt; }}
.bar td {{ background-color: #b6d4f1; border: 1px solid #5d88b4; padding: 7px 10px; font-weight: bold;
    font-size: 9.5pt; }}
.bar2 td {{ background-color: #e7f0fc; border: 1px solid #5d88b4; padding: 7px 10px; font-weight: bold;
    font-size: 9.5pt; }}
.bar .right, .bar2 .right {{ text-align: right; }}
.result td {{ background-color: #d4e8fa; border: 1px solid #5d88b4; text-align: center; padding: 5px;
    font-weight: bold; font-size: 10pt; }}

.box td {{ border: 1px solid #9da7b2; padding: 6px 8px; font-size: 8.5pt; }}
.box-title {{ font-weight: bold; color: #193d63; font-size: 8.5pt; padding-bottom: 3px; }}
.key td {{ border: 1px solid #c4ccd6; padding: 3px 4px; font-size: 7.5pt; text-align: center; }}
.key .label {{ font-weight: bold; }}

.sign td {{ text-align: center; font-size: 8.5pt; font-weight: bold; padding-top: 5px;
    border-top: 1px solid #53677b; }}
.foot {{ font-size: 7pt; color: #6b7280; text-align: center; padding-top: 8px; }}
"""


def spacer(height: int) -> str:
    return f'<table><tr><td style="height: {height}px; font-size: 1pt;">&nbsp;</td></tr></table>'


def number(value) -> str:
    """19, 19.5, 87.25 - marks as a marksheet writes them."""
    if value is None:
        return "-"

    text = f"{decimal.Decimal(value).quantize(decimal.Decimal('0.01')):f}"

    return text.rstrip("0").rstrip(".") if "." in text else text


def percent(value) -> str:
    return "-" if value is None else f"{decimal.Decimal(value).quantize(decimal.Decimal('0.01'))}"


def meta_row(key: str, value) -> str:
    shown = "" if value in (None, "") else e(value)
    return f'<tr><td class="k">{e(key)}</td><td class="colon">:</td><td>{shown}</td></tr>'


def header(school, session: str) -> str:
    logo = pdf_design.stored_logo_data_uri(school) or pdf_design.logo_data_uri(school.logo_url)
    size = pdf_design.logo_size(logo) if logo else None
    image = ""

    if size:
        width = min(size[0], 58)
        image = f'<img src="{logo}" width="{width}" height="{round(size[1] * width / size[0])}">'

    address = pdf_design.joined(school.address, school.city, school.state)

    return f"""
    <table class="head"><tr>
        <td class="logo-cell">{image}</td>
        <td class="middle">
            <div class="school">{e(school.name.upper())}</div>
            {f'<div class="sub">{e(address.upper())}</div>' if address else ""}
            {f'<div class="sub">PH : {e(school.phone)}</div>' if school.phone else ""}
            <div class="doc">Report Card</div>
        </td>
    </tr></table>
    <div class="session">Academic Session : {e(session)}</div>"""


def student_block(student, year_id: int) -> str:
    enrollment = (
        StudentEnrollment.objects.select_related("school_class", "class_section")
        .filter(student_id=student.id, academic_year_id=year_id)
        .first()
    )
    class_name = enrollment.school_class.name if enrollment is not None else None
    section = enrollment.class_section.name if enrollment is not None and enrollment.class_section_id else None
    roll = (enrollment.roll_number if enrollment is not None else None) or student.roll_number
    parents = parent_names(student)

    left = [("Admission No", student.admission_number), ("Name of Student", student.name.upper())]

    if parents.father:
        left.append(("Father's Name", parents.father.upper()))

    if parents.mother:
        left.append(("Mother's Name", parents.mother.upper()))

    if not parents.father and not parents.mother:
        left.append(("Guardian's Name", (parents.guardian or "").upper()))

    left.append(("Address", (student.address or "").upper()))
    right = [("Roll No", roll), ("Class", class_name), ("Section", section)]

    return f"""
    <table><tr>
        <td style="width: 52%"><table class="meta">{"".join(meta_row(k, v) for k, v in left)}</table></td>
        <td style="width: 34%"><table class="meta">{"".join(meta_row(k, v) for k, v in right)}</table></td>
        <td style="width: 14%"><table class="photo"><tr><td>STUDENT<br/>PHOTO</td></tr></table></td>
    </tr></table>"""


def term_span(card, columns) -> int:
    if card.kind == GradeScaleKind.GRADES:
        return 1

    return len(columns) + (3 if card.kind == GradeScaleKind.GPA else 2)


def uniform_possible(card, term_id) -> decimal.Decimal | None:
    """The marks every subject's term total is out of, when it is the same
    for all of them - so the header can say "Marks (100)"."""
    possible = {row.terms[term_id].possible for row in card.subjects if row.terms[term_id].possible > 0}

    return next(iter(possible)) if len(possible) == 1 else None


def marks_table(card) -> str:
    gpa = card.kind == GradeScaleKind.GPA
    grades_only = card.kind == GradeScaleKind.GRADES

    top = ['<th rowspan="2" style="width: 14%">SUBJECT</th>']
    second = []

    for term in card.terms:
        columns = card.columns[term.id]
        possible = uniform_possible(card, term.id)
        out_of = f" ({number(possible)} Marks)" if possible is not None and not grades_only else ""
        top.append(f'<th class="term" colspan="{term_span(card, columns)}">{e(term.name.upper())}{out_of}</th>')

        if grades_only:
            second.append("<th>Grade</th>")
            continue

        for column in columns:
            limit = f"<br/>({number(column.out_of)})" if column.out_of is not None else ""
            second.append(f"<th>{e(column.title.upper())}{limit}</th>")

        second.append(f"<th>Marks{'<br/>(' + number(possible) + ')' if possible is not None else ''}</th>")
        second.append("<th>Grade</th>")

        if gpa:
            second.append("<th>GP</th>")

    rows = []

    for row in card.subjects:
        cells = [f'<td class="subject">{e(row.name)}</td>']

        for term in card.terms:
            total = row.terms[term.id]
            grade_class = "fail" if total.failing else "strong"

            if grades_only:
                cells.append(f'<td class="{grade_class}">{e(total.grade or "-")}</td>')
                continue

            for column in card.columns[term.id]:
                mark = row.marks.get(term.id, {}).get(column.title)

                if mark is None:
                    shown = "-"
                elif mark.absent:
                    shown = "AB"
                elif column.out_of is None:
                    shown = f"{number(mark.obtained)}/{number(mark.max_marks)}"
                else:
                    shown = number(mark.obtained)

                cells.append(f"<td>{shown}</td>")

            uniform = uniform_possible(card, term.id) is not None
            marks = number(total.obtained) if uniform else f"{number(total.obtained)}/{number(total.possible)}"
            cells.append(f'<td class="strong">{marks if total.possible > 0 else "-"}</td>')
            cells.append(f'<td class="{grade_class}">{e(total.grade or "-")}</td>')

            if gpa:
                cells.append(f"<td>{number(total.grade_point)}</td>")

        rows.append(f"<tr>{''.join(cells)}</tr>")

    if not rows:
        span = 1 + sum(term_span(card, card.columns[term.id]) for term in card.terms)
        rows.append(f'<tr><td colspan="{span}">No published results yet for this year.</td></tr>')

    return f"""
    <table class="marks">
        <tr>{''.join(top)}</tr>
        <tr>{''.join(second)}</tr>
        {''.join(rows)}
    </table>"""


def term_figure(card, term) -> str:
    total = card.term_totals[term.id]

    if card.kind == GradeScaleKind.GRADES:
        return f"{e(term.name)} Grade : {e(total.grade or '-')}"

    if card.kind == GradeScaleKind.GPA:
        return f"{e(term.name)} GPA : {number(card.gpa_by_term[term.id])} / {number(card.max_point)}"

    if total.possible <= 0:
        return f"{e(term.name)} Marks : -"

    return f"{e(term.name)} Marks : {number(total.obtained)} / {number(total.possible)}<br/>{percent(total.percentage)}%"


def totals(card, attendance: dict, rank: int | None, settings: dict) -> str:
    cells = [f"<td>{term_figure(card, term)}</td>" for term in card.terms]
    working = attendance.get("working_days") or 0
    cells.append(f"<td>Attendance : {attendance.get('present', 0)} / {working}</td>" if working else "<td>Attendance : -</td>")
    mini = f'<table class="mini"><tr>{"".join(cells)}</tr></table>'

    overall = card.overall
    rank_text = f"RANK : {rank}" if rank is not None else ""

    if card.kind == GradeScaleKind.GRADES:
        bars = f"""<table class="bar"><tr><td width="50%">FINAL GRADE : {e(overall.grade or "-")}</td>
            <td width="50%" class="right">{rank_text}</td></tr></table>"""
    elif card.kind == GradeScaleKind.GPA:
        equivalent = ""

        if card.multiplier is not None and card.gpa is not None:
            equivalent = f"EQUIVALENT PERCENTAGE : {percent(card.gpa * card.multiplier)}%"

        bars = f"""<table class="bar"><tr><td width="50%">FINAL GPA : {number(card.gpa)} / {number(card.max_point)}</td>
            <td width="50%" class="right">FINAL GRADE : {e(overall.grade or "-")}</td></tr></table>
            <table class="bar2"><tr><td width="50%">{equivalent}</td><td width="50%" class="right">{rank_text}</td></tr></table>"""
    else:
        bars = f"""<table class="bar"><tr>
            <td width="50%">OVERALL MARKS : {number(overall.obtained)} / {number(overall.possible)}</td>
            <td width="50%" class="right">FINAL PERCENTAGE : {percent(overall.percentage)}%</td></tr></table>
            <table class="bar2"><tr><td width="50%">FINAL GRADE : {e(overall.grade or "-")}</td>
            <td width="50%" class="right">{rank_text}</td></tr></table>"""

    result = ""

    if card.passed is not None:
        word = settings["result_pass_word"] if card.passed else settings["result_fail_word"]
        result = f'{spacer(4)}<table class="result"><tr><td>RESULT : {e(word)}</td></tr></table>'

    return f"{mini}{spacer(6)}{bars}{result}"


def grading_key(scale) -> str:
    if scale is None:
        return ""

    bands = sorted(scale.bands.all(), key=lambda band: band.min_percentage, reverse=True)
    gpa = scale.kind == GradeScaleKind.GPA
    # Fixed widths: a column whose cells are all short (or empty) would
    # otherwise be squeezed to nothing.
    each = f"{84 / max(len(bands), 1):.2f}%"

    def cell(text: str, label: bool = False) -> str:
        css = ' class="label"' if label else ""
        return f'<td width="{each}"{css}>{text}</td>'

    head = ['<td width="16%" class="label">Grade</td>'] + [cell(e(band.label), label=True) for band in bands]
    ranges = ['<td width="16%">Marks %</td>'] + [
        cell(f"{number(band.min_percentage)}-{number(band.max_percentage)}") for band in bands
    ]
    rows = [head, ranges]

    if gpa:
        rows.append(['<td width="16%">Grade point</td>'] + [cell(number(band.grade_point)) for band in bands])

    if any(band.description for band in bands):
        rows.append(['<td width="16%">Meaning</td>'] + [cell(e(band.description or "")) for band in bands])

    return '<table class="key">' + "".join(f"<tr>{''.join(row)}</tr>" for row in rows) + "</table>"


def box(title: str, inner: str) -> str:
    return f"""{spacer(6)}<table class="box"><tr><td><div class="box-title">{e(title)}</div>{inner}</td></tr></table>"""


def paragraphs(text: str) -> str:
    return "<br/>".join(e(line) for line in text.splitlines())


def document(student, through: AcademicTerm, *, school, generated_at: str) -> str:
    card, extra = report_card.load(student, through)
    settings = extra["settings"]
    scale = extra["scale"]
    terms = card.terms
    year = through.academic_year

    # The register over the terms printed, up to today - the same working-day
    # denominator every attendance figure uses (school/performance.py).
    period = SimpleNamespace(start_date=terms[0].start_date, end_date=through.end_date)
    attendance = StudentPerformance.attendance(student, period, SchoolClock.for_school(school).now().date())

    remark = (
        StudentTermRemark.objects.select_related("written_by")
        .filter(student_id=student.id, academic_term_id=through.id)
        .first()
    )

    sections = []

    if remark is not None and remark.remark:
        by = f'<div style="padding-top: 3px; color: #555555;">{e(remark.written_by.name)}</div>' \
            if remark.written_by_id else ""
        sections.append(box("CLASS TEACHER'S REMARKS", paragraphs(remark.remark) + by))

    if settings.get("report_card_note"):
        sections.append(box("A WORD TO PARENTS", paragraphs(settings["report_card_note"])))

    key = grading_key(scale)
    instructions = settings.get("report_card_instructions") or ""

    # The key is a table of its own under the box, not inside it: a table
    # nested in a padded cell leaves xhtml2pdf no width for its columns.
    if instructions:
        sections.append(box("INSTRUCTIONS AND GRADING SCALE", paragraphs(instructions)))
    elif key:
        sections.append(f'{spacer(6)}<div class="box-title">INSTRUCTIONS AND GRADING SCALE</div>')

    if key:
        sections.append(spacer(3) + key)

    absent_note = (
        "AB: absent - left out of the total, which is out of the tests the student sat."
        if any(mark.absent for row in card.subjects for term in row.marks.values() for mark in term.values())
        else ""
    )

    body = f"""
    {header(school, year.name)}
    {student_block(student, year.id)}
    {spacer(6)}
    {marks_table(card)}
    {spacer(6)}
    {totals(card, attendance, extra["rank"], settings)}
    {''.join(sections)}
    {spacer(46)}
    <table><tr>
        <td style="width: 30%"><table class="sign"><tr><td>CLASS TEACHER SIGNATURE</td></tr></table></td>
        <td style="width: 40%"></td>
        <td style="width: 30%"><table class="sign"><tr><td>PRINCIPAL SIGNATURE &amp; SEAL</td></tr></table></td>
    </tr></table>
    <div class="foot">{e(absent_note) + " " if absent_note else ""}Only published results are counted. Generated {e(generated_at)}. Powered by School365ai</div>"""

    landscape = len(terms) > 2 or sum(term_span(card, card.columns[term.id]) for term in terms) > 14

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Report card - {e(student.name)}</title>
<style>{styles(landscape)}</style></head>
<body>{body}</body></html>"""


def file_name(student, through: AcademicTerm) -> str:
    who = student.admission_number or student.id

    return f"report-card-{_slug(who)}-{_slug(through.academic_year.name)}-{_slug(through.name)}.pdf"


def _slug(value) -> str:
    kept = [character if str(character).isalnum() else "-" for character in str(value)]

    return "".join(kept).strip("-").lower() or "report"

