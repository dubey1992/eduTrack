"""One child's progress report, as a printable page (docs/assessments.md).

The same figures as the Performance dialog, because they are the same
figures: the payload school/performance.py builds is what this lays out.
Nothing here re-derives an average, so a report a guardian files and the
screen a teacher reads cannot disagree.

It adds what the screen does not show - every test inside each subject, with
the mark and **the grade frozen onto it at publish** (a subject average is
worked out when somebody asks; a test's grade was decided the day the result
went out, and that is the one a guardian questioning a report is entitled to
see) - and what a report card carries: the school's band, the child's roll
number, guardian and class teacher, the academic year, the grade scale the
grades were read against, and lines for the class teacher, the principal
and the parent to sign.

Wears the platform's shared PDF look (school/pdf_design.py,
docs/pdf-design.md). Portrait, because this is a document about a person
rather than a table of a school.
"""

from __future__ import annotations

import datetime as dt
import html

from . import dates, pdf_design
from .enums import AssessmentStatus
from .models import AcademicTerm, AssessmentMark, Student

REPORT_STYLES = """
table.marks th { font-size: 7.5pt; padding: 6px 5px; }
table.marks td { font-size: 8.5pt; padding: 5px 5px; }
.marks .subject-name { font-weight: bold; }
.marks .weak { font-size: 7pt; color: #b91c1c; }
.marks .grade { font-weight: bold; color: #1e3a8a; }
.marks .grade-fail { font-weight: bold; color: #b91c1c; }
.marks .absent { color: #b91c1c; }
.marks .up { color: #047857; font-weight: bold; }
.marks .down { color: #b91c1c; font-weight: bold; }
.says td { font-size: 9.5pt; padding: 4px 10px; border-left: 3px solid #2563eb; background-color: #f8fafc; }
.steps td { font-size: 9.5pt; padding: 4px 10px; border-left: 3px solid #059669; background-color: #ecfdf5; }
.scale td.band-cell { border: 1px solid #e5e7eb; padding: 5px 6px; text-align: center; font-size: 10pt; }
.scale .band-range { font-size: 7.5pt; color: #6b7280; padding-top: 2px; }
.legend { font-size: 7.5pt; color: #6b7280; padding-top: 4px; }
.remark td { font-size: 10pt; padding: 8px 12px; border-left: 3px solid #7c3aed; background-color: #f5f3ff;
    line-height: 1.5; }
.remark-by { font-size: 8pt; color: #6b7280; padding-top: 4px; }
.empty { font-size: 9.5pt; color: #6b7280; padding: 8px 10px; background-color: #f8fafc; }
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


def render(payload: dict, *, school, generated_at: str) -> bytes:
    return pdf_design.render(document(payload, school=school, generated_at=generated_at), file_name(payload))


def document(payload: dict, *, school, generated_at: str) -> str:
    """The report as HTML. Separate from render() so a test can read it."""
    student = payload["student"]
    term = payload["term"]
    subjects = payload["subjects"]
    record = (
        Student.objects.select_related("class_section__class_teacher").filter(pk=student["id"]).first()
    )
    marks = tests_of(payload)

    period = None if term is None else dates.range_label(
        dt.date.fromisoformat(term["start_date"]), dt.date.fromisoformat(term["end_date"])
    )
    term_name = "No term" if term is None else term["name"]
    year = None
    if term is not None:
        found = AcademicTerm.objects.select_related("academic_year").filter(pk=term["id"]).first()
        year = found.academic_year.name if found is not None else None

    section = record.class_section if record is not None and record.class_section_id else None
    teacher = section.class_teacher if section is not None and section.class_teacher_id else None

    who = pdf_design.facts([
        ("Name", student["name"]),
        ("Admission no.", student["admission_number"]),
        ("Roll no.", record.roll_number if record is not None else None),
        ("Class", student["class_section_name"]),
        ("Guardian", record.guardian_name if record is not None else None),
        ("Class teacher", teacher.name if teacher is not None else None),
    ])
    when = pdf_design.facts([
        ("Academic year", year),
        ("Term", term_name),
        ("Period", period),
        ("Generated", generated_at),
    ])

    closing = [
        "Only published results are counted. A test the student missed is left out of the average rather than "
        "counted as nought, and each subject weighs the same in the overall figure.",
        f"Generated {generated_at}." if generated_at else "",
        "Powered by School365ai",
    ]

    body = f"""
    {pdf_design.school_band(school, "PROGRESS REPORT", term_name, period)}
    {pdf_design.spacer(16)}
    {pdf_design.side_by_side(who, when, "Student", "Report")}

    {results(payload, subjects, marks)}

    {pdf_design.section("Attendance")}
    {attendance_block(payload["attendance"])}

    {says(payload["insights"])}
    {next_steps(payload.get("recommendations") or [])}
    {remark_block(payload.get("remark"))}

    {pdf_design.spacer(10)}
    {pdf_design.signatures(["Class teacher", "Principal", "Parent / Guardian"])}
    {pdf_design.closing([line for line in closing if line])}
"""

    return pdf_design.page(
        f"Progress report - {student['name']}", body,
        footer=f"{school.name} - Progress report - {student['name']} - {term_name}",
        extra_styles=REPORT_STYLES,
    )


# -- the results ------------------------------------------------------------------


def results(payload: dict, subjects: list, marks: list) -> str:
    """The marks, or a plain sentence where there are none.

    A term nobody has published a result in is not a term the child failed,
    so it says so in words rather than printing a table of dashes.
    """
    if payload["term"] is None:
        return f'{pdf_design.section("Results")}<div class="empty">This school has not set its terms out yet.</div>'

    if not subjects:
        return (
            f'{pdf_design.section("Results")}'
            '<div class="empty">No result has been published for this term yet.</div>'
        )

    # Imported here: performance reaches school/services.py, which imports
    # this module while it loads.
    from .performance import StudentPerformance

    scale = StudentPerformance.grade_scale_for(marks)

    return f"""
    {pdf_design.section("Summary")}
    {summary_tiles(payload)}

    {pdf_design.section("Subjects")}
    {subject_table(payload, subjects, scale)}

    {topic_section(payload, subjects)}

    {pdf_design.section("Every test this term")}
    {test_table(marks, scale)}

    {grade_scale(scale)}"""


def summary_tiles(payload: dict) -> str:
    overall = payload["overall"]
    weak = payload.get("weak_below_percentage")
    average = overall["average_percentage"]
    moved = overall["change"]
    tests = overall["assessments"]
    missed = overall["absent"]

    def tone_of_average():
        if average is None:
            return "neutral"
        if weak is not None and float(average) < float(weak):
            return "danger"
        return "success"

    def tone_of_change():
        if moved is None or float(moved) == 0:
            return "neutral"
        return "success" if float(moved) > 0 else "danger"

    return pdf_design.tiles([
        {"label": "Average", "value": percent(average), "tone": tone_of_average(),
         "hint": f"{text(overall['subjects'])} subject{'s' if overall['subjects'] != 1 else ''}"},
        {"label": "Class average", "value": percent(overall["class_average_percentage"]), "tone": "info"},
        {"label": "Change", "value": change(moved), "tone": tone_of_change(),
         "hint": f"Previous term {percent(overall['previous_average_percentage'])}"},
        {"label": "Tests", "value": text(tests), "tone": "danger" if missed else "neutral",
         "hint": f"{text(missed)} missed"},
    ])


def failing_grades(scale) -> set[str]:
    if scale is None:
        return set()

    return {band.label for band in scale.bands.all() if band.is_failing}


def grade_cell(grade, scale) -> str:
    if not grade:
        return "-"

    css = "grade-fail" if grade in failing_grades(scale) else "grade"

    return f'<span class="{css}">{text(grade)}</span>'


def subject_table(payload: dict, subjects: list, scale) -> str:
    weak = payload.get("weak_below_percentage")
    rows = []

    for subject in subjects:
        average = subject["average_percentage"]
        flag = ""
        if weak is not None and average is not None and float(average) < float(weak):
            flag = f'<div class="weak">below {text(weak)}%</div>'

        rows.append([
            f'<span class="subject-name">{text(subject["subject_name"])}</span>{flag}',
            text(subject["assessments"]),
            text(subject["absent"]),
            percent(average),
            grade_cell(subject["grade"], scale),
            percent(subject["class_average_percentage"]),
            percent(subject["previous_average_percentage"]),
            change_cell(subject["change"]),
        ])

    return pdf_design.table(
        [("Subject", "24%", False), ("Tests", "8%", True), ("Missed", "9%", True), ("Average", "16%", True),
         ("Grade", "9%", False), ("Class average", "12%", True), ("Previous", "11%", True), ("Change", "11%", True)],
        rows, table_class="items marks",
    )


def topic_section(payload: dict, subjects: list) -> str:
    """Which parts of each subject the tests named (docs/insights.md).

    Left out entirely where no test named a chapter - a school that does
    not fill the field in should see nothing here, not a table of dashes.
    """
    with_topics = [subject for subject in subjects if subject.get("topics")]

    if not with_topics:
        return ""

    weak = payload.get("weak_below_percentage")
    rows = []

    for subject in with_topics:
        for topic in subject["topics"]:
            average = topic["average_percentage"]
            flag = ""
            if weak is not None and average is not None and float(average) < float(weak):
                flag = f'<div class="weak">below {text(weak)}%</div>'

            rows.append([
                text(subject["subject_name"]),
                f"{text(topic['topic_name'])}{flag}",
                text(topic["assessments"]),
                text(topic["absent"]),
                percent(average),
            ])

    table = pdf_design.table(
        [("Subject", "24%", False), ("Topic", "40%", False), ("Tests", "12%", True), ("Missed", "12%", True),
         ("Average", "12%", True)],
        rows, table_class="items marks",
    )

    return f'{pdf_design.section("Inside each subject")}{table}'


def test_table(marks: list, scale) -> str:
    """Every test behind the averages above, with the grade frozen on it.

    Read from the same published marks the payload was built from, so this
    adds detail rather than a second opinion.
    """
    rows = []

    for mark in marks:
        assessment = mark.assessment
        absent = mark.is_absent

        rows.append([
            text(assessment.subject.name),
            text(assessment.title),
            text(dates.us(assessment.assessment_date)),
            # Absent is said in words. A blank would read as a nought, and a
            # nought would be a lie about a child who was not there.
            '<span class="absent">Absent</span>' if absent else text(number(mark.marks_obtained)),
            text(number(assessment.max_marks)),
            "-" if absent else percent(share(mark, assessment)),
            grade_cell(mark.grade, scale),
        ])

    return pdf_design.table(
        [("Subject", "20%", False), ("Test", "28%", False), ("Date", "13%", False), ("Marks", "10%", True),
         ("Out of", "10%", True), ("%", "10%", True), ("Grade", "9%", False)],
        rows, empty="No published test this term.", table_class="items marks",
    )


def grade_scale(scale) -> str:
    """The bands the grades above were read against, so a guardian can see
    what a B means at this school: one strip, best grade first, a failing
    grade in red."""
    if scale is None:
        return ""

    bands = sorted(scale.bands.all(), key=lambda band: band.min_percentage, reverse=True)

    if not bands:
        return ""

    per_row = 8
    width = f"{100 / per_row:.2f}%"
    rows = []

    for start in range(0, len(bands), per_row):
        cells = [
            f'<td class="band-cell" width="{width}">{grade_cell(band.label, scale)}'
            f'<div class="band-range">{text(number(band.min_percentage))}-{text(number(band.max_percentage))}%</div></td>'
            for band in bands[start:start + per_row]
        ]
        cells += [f'<td width="{width}"></td>'] * (per_row - len(cells))
        rows.append(f"<tr>{''.join(cells)}</tr>")

    failing = " A grade in red is below the pass mark." if failing_grades(scale) else ""

    return (
        f'{pdf_design.section(f"Grade scale - {scale.name}")}'
        f'<table class="marks scale">{"".join(rows)}</table>'
        f'<div class="legend">Each subject average and test above is graded on this scale.{failing}</div>'
    )


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


# -- attendance and what the figures say ----------------------------------------------


def attendance_block(attendance: dict) -> str:
    """The register for the same period.

    Two things are deliberately not printed as 0%. A period the school
    never opened has no rate to state; and a period whose register was
    never taken reads as 0% out of the working days, which is a fact about
    the school's paperwork and would be read - on a page going home - as a
    child who attended nothing. school/insights.py refuses to speak from
    that same blank, and this refuses to print from it.
    """
    if not attendance["working_days"]:
        return '<div class="empty">The school ran on no day of this period, so there is no attendance to report.</div>'

    marked = attendance["present"] + attendance["absent"] + attendance["leave"]

    if not marked:
        return (
            f'<div class="empty">The register was not taken in this period. The school ran '
            f'{text(attendance["working_days"])} days and {text(attendance["not_marked"])} were not marked.</div>'
        )

    return pdf_design.tiles([
        {"label": "Attendance", "value": percent(attendance["attendance_rate"]), "tone": "info"},
        {"label": "Present", "value": text(attendance["present"]), "tone": "success"},
        {"label": "Absent", "value": text(attendance["absent"]),
         "tone": "danger" if attendance["absent"] else "neutral"},
        {"label": "Leave", "value": text(attendance["leave"])},
        {"label": "School days", "value": text(attendance["working_days"])},
        {"label": "Not marked", "value": text(attendance["not_marked"])},
    ], per_row=6)


def says(insights: list) -> str:
    """The rules' sentences, each drawn from a figure already on the page."""
    if not insights:
        return ""

    rows = "".join(f'<tr><td>{text(insight["message"])}</td></tr>' for insight in insights)

    return f'{pdf_design.section("What this looks like")}<table class="says">{rows}</table>'


def remark_block(remark: dict | None) -> str:
    """The class teacher's remark for the term, in their words - left out
    entirely when nobody has written one."""
    if not remark or not remark.get("text"):
        return ""

    by = f'<div class="remark-by">{text(remark["written_by"])}</div>' if remark.get("written_by") else ""
    body = "<br/>".join(text(line) for line in str(remark["text"]).splitlines())

    heading = pdf_design.section("Class teacher's remark")

    return f'{heading}<table class="remark"><tr><td>{body}{by}</td></tr></table>'


def next_steps(recommendations: list) -> str:
    """What to do about the figures above (docs/insights.md).

    Printed under its own heading rather than mixed into the findings: a
    guardian reading this at a kitchen table should be able to tell what
    the school is saying from what it is suggesting.
    """
    if not recommendations:
        return ""

    rows = "".join(f'<tr><td>{text(step["message"])}</td></tr>' for step in recommendations)

    return f'{pdf_design.section("What to do next")}<table class="steps">{rows}</table>'


# -- figures ----------------------------------------------------------------------------


def percent(value) -> str:
    return "-" if value is None else f"{text(number(value))}%"


def change(value) -> str:
    """Points gained or lost, with the sign that says which."""
    if value is None:
        return "-"

    figure = float(value)
    sign = "+" if figure > 0 else ""

    return f"{sign}{text(number(value))}"


def change_cell(value) -> str:
    if value is None or float(value) == 0:
        return change(value)

    return f'<span class="{"up" if float(value) > 0 else "down"}">{change(value)}</span>'


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
