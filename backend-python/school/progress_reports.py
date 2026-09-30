"""One child's progress report, as a printable page (docs/assessments.md).

The same figures as the Performance dialog, because they are the same
figures: the payload school/performance.py builds is what this lays out.
Nothing here re-derives an average, so a report a guardian files and the
screen a teacher reads cannot disagree.

It adds one thing the screen does not show - every test inside each
subject, with the mark and **the grade frozen onto it at publish**. A
subject average is worked out when somebody asks; a test's grade was
decided the day the result went out, and that is the one a guardian
questioning a report is entitled to see, whatever the school has done to
its grade bands since.

Rendered with xhtml2pdf like the receipt and the payslip, for the same
reason: shared hosting has no cairo or pango. Portrait, because this is a
document about a person rather than a table of a school.
"""

from __future__ import annotations

import html
import io

from xhtml2pdf import pisa

from . import dates
from .enums import AssessmentStatus
from .models import AssessmentMark
from .receipts import STYLESHEET, e

STYLES = """
@page {
    size: a4 portrait;
    margin: 16mm 14mm 18mm 14mm;
    @frame footer { -pdf-frame-content: page-footer; bottom: 9mm; height: 8mm; margin-left: 14mm; margin-right: 14mm; }
}
.sheet { padding: 0; }
h1 { font-size: 15px; margin: 18px 0 8px; }
.facts td { padding: 3px 14px 3px 0; font-size: 11px; vertical-align: top; }
.facts .key { color: #6b7280; width: 120px; }
.grid { margin-top: 6px; border: 1px solid #d7dbe3; }
.grid th { background: #f3f4f6; text-align: left; font-size: 10px; padding: 5px 7px; border-bottom: 1px solid #d7dbe3; }
.grid td { font-size: 10px; padding: 4px 7px; border-bottom: 1px solid #eceef2; }
.grid th.num, .grid td.num { text-align: right; }
.tests th { font-size: 9px; }
.tests td { font-size: 9px; color: #4b5563; }
.subject-name { font-weight: bold; }
.says li { font-size: 11px; margin-bottom: 3px; }
.foot { font-size: 9px; color: #6b7280; }
.foot .right { text-align: right; }
"""


def file_name(payload: dict) -> str:
    """Named for the child and the term, so a folder of them sorts and no
    two downloads overwrite one another."""
    student = payload["student"]
    term = payload["term"]
    who = student["admission_number"] or student["id"]
    when = "no-term" if term is None else term["name"]

    return f"progress-report-{slug(who)}-{slug(when)}.pdf"


def slug(value) -> str:
    """A filename part: letters, digits and hyphens, nothing a browser or a
    filesystem has to think about."""
    kept = [character if str(character).isalnum() else "-" for character in str(value)]

    return "".join(kept).strip("-").lower() or "report"


def render(payload: dict, *, school_name: str, generated_at: str) -> bytes:
    out = io.BytesIO()
    result = pisa.CreatePDF(
        document(payload, school_name=school_name, generated_at=generated_at), dest=out, encoding="utf-8"
    )

    if result.err:
        raise RuntimeError(f"Could not render {file_name(payload)}")

    return out.getvalue()


def document(payload: dict, *, school_name: str, generated_at: str) -> str:
    """The report as HTML. Separate from render() so a test can read it."""
    student = payload["student"]
    term = payload["term"]
    subjects = payload["subjects"]

    period = "-" if term is None else f"{dates.us_from_iso(term['start_date'])} to {dates.us_from_iso(term['end_date'])}"
    term_name = "No term" if term is None else term["name"]

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>{STYLESHEET}{STYLES}</style></head>
<body>
<div id="page-footer">
    <table class="foot"><tr>
        <td>{e(school_name)} &#183; Progress report &#183; {e(student["name"])}</td>
        <td class="right">Page <pdf:pagenumber> of <pdf:pagecount></td>
    </tr></table>
</div>
<div class="sheet">
    <table class="head"><tr>
        <td><div class="brand">{e(school_name)}</div><div class="muted">Progress report</div></td>
        <td class="right"><div>{text(term_name)}</div><div class="muted">{text(period)}</div></td>
    </tr></table>

    <h1>Student</h1>
    <table class="facts">
        <tr><td class="key">Name</td><td>{text(student["name"])}</td></tr>
        <tr><td class="key">Admission No.</td><td>{text(student["admission_number"] or "-")}</td></tr>
        <tr><td class="key">Class</td><td>{text(student["class_section_name"] or "-")}</td></tr>
        <tr><td class="key">Term</td><td>{text(term_name)}</td></tr>
    </table>

    {body(payload, subjects)}

    <h1>Attendance</h1>
    {attendance_table(payload["attendance"])}

    {says(payload["insights"])}

    <div class="note muted">
        Only published results are counted. A test the student missed is left out of the average rather than
        counted as nought, and each subject weighs the same in the overall figure.
        Generated {text(generated_at)}.
    </div>
</div>
</body>
</html>"""


def body(payload: dict, subjects: list) -> str:
    """The marks, or a plain sentence where there are none.

    A term nobody has published a result in is not a term the child failed,
    so it says so in words rather than printing a table of dashes.
    """
    if payload["term"] is None:
        return '<h1>Results</h1><p class="muted">This school has not set its terms out yet.</p>'

    if not subjects:
        return '<h1>Results</h1><p class="muted">No result has been published for this term yet.</p>'

    return f"""<h1>Summary</h1>
    {summary_table(payload)}

    <h1>Subjects</h1>
    {subject_table(payload, subjects)}

    <h1>Tests</h1>
    {test_table(payload, subjects)}"""


def summary_table(payload: dict) -> str:
    overall = payload["overall"]
    lines = [
        ("Average", percent(overall["average_percentage"])),
        ("Class average", percent(overall["class_average_percentage"])),
        ("Previous term", percent(overall["previous_average_percentage"])),
        ("Change", change(overall["change"])),
        ("Subjects", text(overall["subjects"])),
        ("Tests", text(overall["assessments"])),
        ("Missed", text(overall["absent"])),
    ]

    return facts(lines)


def subject_table(payload: dict, subjects: list) -> str:
    weak = payload.get("weak_below_percentage")
    head = (
        "<tr><th>Subject</th><th class='num'>Tests</th><th class='num'>Missed</th><th class='num'>Average</th>"
        "<th>Grade</th><th class='num'>Class average</th><th class='num'>Previous</th><th class='num'>Change</th></tr>"
    )
    rows = []

    for subject in subjects:
        average = subject["average_percentage"]
        flag = ""
        if weak is not None and average is not None and float(average) < float(weak):
            flag = f' <span class="muted">(below {text(weak)}%)</span>'

        rows.append(
            f'<tr><td class="subject-name">{text(subject["subject_name"])}{flag}</td>'
            f'<td class="num">{text(subject["assessments"])}</td>'
            f'<td class="num">{text(subject["absent"])}</td>'
            f'<td class="num">{percent(average)}</td>'
            f'<td>{text(subject["grade"] or "-")}</td>'
            f'<td class="num">{percent(subject["class_average_percentage"])}</td>'
            f'<td class="num">{percent(subject["previous_average_percentage"])}</td>'
            f'<td class="num">{change(subject["change"])}</td></tr>'
        )

    return f'<table class="grid"><thead>{head}</thead><tbody>{"".join(rows)}</tbody></table>'


def test_table(payload: dict, subjects: list) -> str:
    """Every test behind the averages above, with the grade frozen on it.

    Read from the same published marks the payload was built from, so this
    adds detail rather than a second opinion.
    """
    marks = tests_of(payload)

    if not marks:
        return '<p class="muted">-</p>'

    head = (
        "<tr><th>Subject</th><th>Test</th><th>Date</th><th class='num'>Marks</th>"
        "<th class='num'>Out of</th><th class='num'>%</th><th>Grade</th></tr>"
    )
    rows = []

    for mark in marks:
        assessment = mark.assessment
        absent = mark.is_absent

        rows.append(
            f"<tr><td>{text(assessment.subject.name)}</td>"
            f"<td>{text(assessment.title)}</td>"
            f"<td>{text(dates.us(assessment.assessment_date))}</td>"
            # Absent is said in words. A blank would read as a nought, and a
            # nought would be a lie about a child who was not there.
            f'<td class="num">{"Absent" if absent else text(number(mark.marks_obtained))}</td>'
            f'<td class="num">{text(number(assessment.max_marks))}</td>'
            f'<td class="num">{"-" if absent else percent(share(mark, assessment))}</td>'
            f'<td>{text(mark.grade or "-")}</td></tr>'
        )

    return f'<table class="grid tests"><thead>{head}</thead><tbody>{"".join(rows)}</tbody></table>'


def tests_of(payload: dict):
    term = payload["term"]

    if term is None:
        return []

    return list(
        AssessmentMark.objects.filter(
            student_id=payload["student"]["id"],
            assessment__academic_term_id=term["id"],
            assessment__status=AssessmentStatus.PUBLISHED,
        )
        .select_related("assessment", "assessment__subject")
        .order_by("assessment__subject__name", "assessment__assessment_date", "assessment_id")
    )


def share(mark, assessment):
    """One mark as a percentage, for the detail line."""
    if mark.marks_obtained is None or not assessment.max_marks:
        return None

    return mark.marks_obtained / assessment.max_marks * 100


def attendance_table(attendance: dict) -> str:
    """The register for the same period.

    Two things are deliberately not printed as 0%. A period the school
    never opened has no rate to state; and a period whose register was
    never taken reads as 0% out of the working days, which is a fact about
    the school's paperwork and would be read - on a page going home - as a
    child who attended nothing. school/insights.py refuses to speak from
    that same blank, and this refuses to print from it.
    """
    if not attendance["working_days"]:
        return '<p class="muted">The school ran on no day of this period, so there is no attendance to report.</p>'

    marked = attendance["present"] + attendance["absent"] + attendance["leave"]

    if not marked:
        return facts([
            ("Attendance", "The register was not taken in this period."),
            ("School days", text(attendance["working_days"])),
            ("Not marked", text(attendance["not_marked"])),
        ])

    return facts([
        ("Attendance", percent(attendance["attendance_rate"])),
        ("Present", text(attendance["present"])),
        ("Absent", text(attendance["absent"])),
        ("Leave", text(attendance["leave"])),
        ("School days", text(attendance["working_days"])),
        ("Not marked", text(attendance["not_marked"])),
    ])


def says(insights: list) -> str:
    """The rules' sentences, each drawn from a figure already on the page."""
    if not insights:
        return ""

    items = "".join(f'<li>{text(insight["message"])}</li>' for insight in insights)

    return f'<h1>What this looks like</h1><ul class="says">{items}</ul>'


def facts(lines: list) -> str:
    cells = "".join(f'<tr><td class="key">{text(key)}</td><td><b>{value}</b></td></tr>' for key, value in lines)

    return f'<table class="facts">{cells}</table>'


def percent(value) -> str:
    return "-" if value is None else f"{text(number(value))}%"


def change(value) -> str:
    """Points gained or lost, with the sign that says which."""
    if value is None:
        return "-"

    figure = float(value)
    sign = "+" if figure > 0 else ""

    return f"{sign}{text(number(value))}"


def number(value) -> str:
    """A figure as a person writes it: 34 rather than 34.00, 72.5 not
    72.50."""
    if value is None:
        return "-"

    text_value = str(value)

    if "." in text_value:
        text_value = text_value.rstrip("0").rstrip(".")

    return text_value or "0"


def text(value) -> str:
    """Escaped, keeping a zero - the receipt's e() reads 0 as nothing."""
    return html.escape(str(value))
