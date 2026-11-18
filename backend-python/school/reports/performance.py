"""The two performance reports (docs/assessments.md, slice 13).

Two views of the same marks, which is why they share a module and the query
that reads them:

- **Student performance** - one line per student: what they averaged, the
  grade it earns, how the class did on the same tests, and whether they were
  there. The line a class teacher reads down.
- **Class performance** - one line per class and subject: what the subject
  averaged, its best and worst, and how many students are under the school's
  mark. The line a head of department reads down.

Both are built over a ReportRange like every other report, rather than over
a term. A term is a dated slice of a year, so "Term 1" is asked for by
sending its dates - and reporting by range is what gives these two the
previous-period comparison, the group roll-up and the CSV and PDF for free,
all computed by exactly the same code as the other seven.

The arithmetic is school.marks, the same module a student's own Performance
dialog uses. Nothing here re-derives an average: a figure on the report and
the same figure on the screen cannot disagree, because there is only one of
them.

Four rules carried from the dialog, because a report that broke them would
be the product contradicting itself:

- a draft counts for nothing - only published results are read;
- absent is not zero - an absentee leaves the denominator;
- a student's average weighs each *subject* evenly, not each mark;
- the class average covers exactly the tests the student sat.
"""

from __future__ import annotations

from django.db.models import Count, Sum

from .. import modules
from ..enums import AssessmentStatus, AttendanceStatus, GradeScaleKind
from ..marks import average_of, mean_of, percentage_of
from ..models import AcademicTerm, Assessment, AssessmentMark, Attendance, ClassSection, GradeScale, Student
from ..services import GradeScaleService, php_number, php_round_1
from .range import ReportRange

MODULE = "assessments"


def published_marks(report_range: ReportRange, filters: dict):
    """Every published mark whose test falls inside the range.

    By test date rather than by when the mark was typed: a report about
    September is about the tests September held, whoever got round to
    entering them in October.
    """
    marks = AssessmentMark.objects.filter(
        school_id=report_range.school_id,
        assessment__status=AssessmentStatus.PUBLISHED,
        assessment__assessment_date__gte=report_range.start,
        assessment__assessment_date__lte=report_range.end,
    ).select_related("assessment", "assessment__subject", "student", "student__class_section__school_class")

    if filters.get("class_section_id"):
        marks = marks.filter(assessment__class_section_id=filters["class_section_id"])

    if filters.get("department_id"):
        marks = marks.filter(assessment__subject__department_id=filters["department_id"])

    # A head of department reports on their own departments and no others.
    # Present but empty means they head none, so they see nothing.
    if "department_ids" in filters:
        marks = marks.filter(assessment__subject__department_id__in=filters["department_ids"])

    return marks.order_by("student_id", "assessment__subject__name", "assessment__assessment_date", "assessment_id")


def class_averages(assessment_ids) -> dict:
    """Each test's class average, over everybody who sat it.

    Two queries for the whole report rather than one per test - a school
    with four hundred marks would otherwise ask four hundred times.
    """
    wanted = set(assessment_ids)

    if not wanted:
        return {}

    maximums = dict(Assessment.objects.filter(id__in=wanted).values_list("id", "max_marks"))
    averages = {}

    sat = (
        AssessmentMark.objects.filter(assessment_id__in=wanted, is_absent=False, marks_obtained__isnull=False)
        .values("assessment_id")
        .annotate(students=Count("id"), total=Sum("marks_obtained"))
    )

    for row in sat:
        maximum = maximums.get(row["assessment_id"])

        if not maximum or not row["students"]:
            continue

        averages[row["assessment_id"]] = (row["total"] / row["students"] / maximum * 100)

    return averages


def weak_below(school_id: int):
    """The school's own "this is weak" line, or nothing if it keeps none."""
    value = modules.setting(school_id, MODULE, "weak_below_percentage")

    return None if value is None else float(value)


class Scales:
    """The grade scale each row is read against (docs/document-styles.md).

    One row at a time - a student, or a class and subject - by the scale its
    own tests used, else the school's default. Not one scale for the whole
    report: a school can grade its young classes "grades only" and its
    seniors by GPA, and reading everybody against whichever test came first
    graded half the school on the wrong scale (fixed 2026-11-18). A school
    that grades nothing gets no grades, which is a school that reports marks.
    """

    def __init__(self, school_id: int, marks) -> None:
        ids = {mark.assessment.grade_scale_id for mark in marks if mark.assessment.grade_scale_id}
        self._by_id = {scale.id: scale for scale in GradeScale.objects.prefetch_related("bands").filter(pk__in=ids)}
        self._default = (
            GradeScale.objects.prefetch_related("bands").filter(school_id=school_id, is_default=True).first()
        )

    def of(self, marks) -> GradeScale | None:
        for mark in marks:
            scale = self._by_id.get(mark.assessment.grade_scale_id)
            if scale is not None:
                return scale

        return self._default


def kind_of(scale: GradeScale | None) -> str:
    return GradeScaleKind.PERCENTAGE if scale is None else scale.kind


def band_of(scale: GradeScale | None, percentage):
    return None if scale is None or percentage is None else GradeScaleService.grade_for(scale, percentage)


def points_mean(scale: GradeScale | None, percentages) -> str | None:
    """A GPA: the mean of each figure's grade points on a GPA scale, as the
    report card works it out; nothing on any other scale."""
    if kind_of(scale) != GradeScaleKind.GPA:
        return None

    points = [band.grade_point for band in (band_of(scale, value) for value in percentages) if band is not None]
    gpa = mean_of([point for point in points if point is not None])

    return None if gpa is None else php_number(float(gpa))


def failing(scale: GradeScale | None, percentage) -> bool:
    """A grades-only scale's "below the mark": a band the school marks as
    failing - the same line its report card's result reads."""
    band = band_of(scale, percentage)

    return band is not None and band.is_failing


def percent(value):
    """A percentage as every other report writes one: one decimal, and a
    whole number without its trailing nought."""
    return None if value is None else php_number(php_round_1(float(value)))


def combined_average(branch_totals: list[dict], count_key: str, average_key: str):
    """One average across a group, weighted by how many each branch counted.

    Never a plain average of the branches' percentages: a branch of nine
    hundred students and one of twelve do not carry the same weight. The
    branch figures are already rounded to a decimal place, so this is
    accurate to a decimal place, which is all any of them is quoted to.
    """
    counted = sum(totals[count_key] or 0 for totals in branch_totals)

    if not counted:
        return None

    total = sum(
        float(totals[average_key]) * (totals[count_key] or 0)
        for totals in branch_totals
        if totals[average_key] is not None
    )

    return percent(total / counted)


def current_term(school_id: int, today):
    """The term today falls in, of the school's current year - or nothing,
    for a school that has not set its terms out."""
    return (
        AcademicTerm.objects.filter(
            school_id=school_id, academic_year__is_current=True, start_date__lte=today, end_date__gte=today
        )
        .order_by("sequence_number", "id")
        .first()
    )


def default_period(school_id: int) -> tuple | None:
    """The period these two reports cover when none is asked for: the current
    term so far, or - for a school with no terms set out - its current year so
    far. Every other report defaults to this month, but class tests come a few
    a term, so "this month" was usually an empty report that read as a broken
    one (2026-11-18). None when the school has neither, and the usual month
    applies."""
    from ..clock import SchoolClock
    from ..models import AcademicYear

    today = SchoolClock.for_school(school_id).now().date()
    term = current_term(school_id, today)

    if term is not None:
        return term.start_date, min(term.end_date, today)

    year = (
        AcademicYear.objects.filter(school_id=school_id, is_current=True, start_date__lte=today)
        .order_by("-start_date")
        .first()
    )

    return None if year is None else (year.start_date, min(year.end_date, today))


def class_order(section) -> tuple:
    """Class 1, 2 ... 10 by the class's level, then the section - never as
    text, where "Class 10" comes straight after "Class 1"."""
    if section is None:
        return (10**6, "", "")

    return (section.school_class.level, section.school_class.name, section.name)


def term_summary(school_id: int, today, department_ids: list | None = None) -> dict:
    """What a school's published results add up to this term - the figure
    the dashboard shows.

    By term rather than by range, because that is the period the card
    names. The rules are the reports': a draft counts for nothing, an
    absentee leaves the average, and a student's average weighs each
    subject evenly. A card that disagreed with the report behind it would
    be worse than no card at all.
    """
    term = current_term(school_id, today)

    if term is None:
        return {"term": None, "average_percentage": None, "students": 0, "students_below_the_mark": 0}

    marks = AssessmentMark.objects.filter(
        school_id=school_id,
        assessment__academic_term_id=term.id,
        assessment__status=AssessmentStatus.PUBLISHED,
        is_absent=False,
    ).select_related("assessment")

    if department_ids is not None:
        marks = marks.filter(assessment__subject__department_id__in=department_ids)

    by_student: dict[int, dict[int, list]] = {}

    for mark in marks:
        percentage = percentage_of(mark)

        if percentage is not None:
            subjects = by_student.setdefault(mark.student_id, {})
            subjects.setdefault(mark.assessment.subject_id, []).append((percentage, mark.assessment.weightage))

    averages = [
        mean_of([average_of(rows) for rows in subjects.values()])
        for subjects in by_student.values()
    ]
    averages = [value for value in averages if value is not None]
    threshold = weak_below(school_id)

    return {
        "term": term.name,
        "average_percentage": percent(sum(averages) / len(averages)) if averages else None,
        "students": len(averages),
        "students_below_the_mark": 0 if threshold is None else sum(
            1 for value in averages if float(value) < threshold
        ),
    }

class StudentPerformanceReport:
    """One line per student: where they stand, and whether they were there."""

    TITLE = "Student performance"
    PDF_NOTE = (
        "Only published results are counted. An absentee leaves the average rather than scoring nought, "
        "and a student's average weighs each subject evenly rather than each test."
    )
    COMPARED_ROWS = [("average_percentage", "Average %")]
    # With no period asked for: the current term so far (see default_period).
    DEFAULT_PERIOD = "term"

    @staticmethod
    def row_key(row: dict):
        return row["student_id"]

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        marks = list(published_marks(report_range, filters))
        threshold = weak_below(report_range.school_id)
        scales = Scales(report_range.school_id, marks)
        averages = class_averages(mark.assessment_id for mark in marks)

        # (student, subject) -> the percentages that count and what was missed.
        counted: dict[int, dict] = {}

        for mark in marks:
            student = counted.setdefault(
                mark.student_id, {"student": mark.student, "subjects": {}, "tests": set(), "marks": []}
            )
            student["tests"].add(mark.assessment_id)
            student["marks"].append(mark)
            subject = student["subjects"].setdefault(
                mark.assessment.subject_id, {"marks": [], "class": [], "assessments": 0, "absent": 0}
            )

            subject["assessments"] += 1

            if mark.assessment_id in averages:
                subject["class"].append(averages[mark.assessment_id])

            if mark.is_absent:
                subject["absent"] += 1
                continue

            percentage = percentage_of(mark)

            if percentage is not None:
                subject["marks"].append((percentage, mark.assessment.weightage))

        attendance = self._attendance(report_range, list(counted))
        rows = []
        behind: dict[int, bool] = {}
        tests_of: dict[int, set] = {}
        order_of: dict[int, tuple] = {}

        for student_id, entry in counted.items():
            student = entry["student"]
            subjects = entry["subjects"]

            # Each subject first, then the subjects evenly - the same order
            # the student's own page works in.
            tests_of[student_id] = entry["tests"]
            order_of[student_id] = class_order(student.class_section)
            per_subject = {key: average_of(value["marks"]) for key, value in subjects.items()}
            average = mean_of(list(per_subject.values()))
            against = mean_of([mean_of(value["class"]) for value in subjects.values()])
            scale = scales.of(entry["marks"])
            kind = kind_of(scale)
            # Grades only: the school shows no marks or percentages, so
            # neither does its report - the grade is the figure.
            grades_only = kind == GradeScaleKind.GRADES
            band = band_of(scale, average)
            behind[student_id] = (
                band is not None and band.is_failing if grades_only
                else threshold is not None and average is not None and float(average) < threshold
            )

            rows.append({
                "student_id": student_id,
                "admission_number": student.admission_number,
                "student": student.name,
                "class_section": self._section_of(student),
                "subjects": len(subjects),
                "assessments": sum(value["assessments"] for value in subjects.values()),
                "absent": sum(value["absent"] for value in subjects.values()),
                "average_percentage": None if grades_only else percent(average),
                "grade": None if band is None else band.label,
                # The mean of the subjects' grade points, on a GPA scale only.
                "gpa": points_mean(scale, per_subject.values()),
                "class_average_percentage": None if grades_only else percent(against),
                "weak_subjects": self._weak(per_subject, threshold, scale),
                "attendance_rate": attendance.get(student_id),
                "grading": kind,
            })

        # Below the line asked for, if one was - the students a report like
        # this is usually run to find.
        if filters.get("below") is not None:
            limit = float(filters["below"])
            rows = [
                row for row in rows
                if row["average_percentage"] is not None and float(row["average_percentage"]) < limit
            ]

        rows.sort(key=lambda row: (order_of[row["student_id"]], row["student"] or "", row["student_id"]))

        # The tests behind these students, each once - not every student's
        # tests added up, which counted one class test twenty-five times.
        held = set().union(*(tests_of[row["student_id"]] for row in rows)) if rows else set()

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": self._totals(rows, len(held), sum(1 for row in rows if behind[row["student_id"]])),
        }

    def headings(self) -> list[str]:
        return [
            "Admission No.", "Student", "Class", "Subjects", "Tests", "Absent", "Average %", "Grade", "GPA",
            "Class average %", "Weak subjects", "Attendance %",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["admission_number"], row["student"], row["class_section"], row["subjects"], row["assessments"],
                row["absent"], row["average_percentage"], row["grade"], row["gpa"], row["class_average_percentage"],
                row["weak_subjects"], row["attendance_rate"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(totals[key] for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "students": total("students"),
            "students_with_a_result": total("students_with_a_result"),
            "tests_held": total("tests_held"),
            "absent": total("absent"),
            "average_percentage": combined_average(branch_totals, "students_with_a_result", "average_percentage"),
            "students_below_the_mark": total("students_below_the_mark"),
            **({
                "average_gpa": combined_average(branch_totals, "students_with_a_gpa", "average_gpa"),
                "students_with_a_gpa": total("students_with_a_gpa"),
            } if any(totals.get("students_with_a_gpa") for totals in branch_totals) else {}),
        }

    @staticmethod
    def _totals(rows: list[dict], tests_held: int, behind: int) -> dict:
        # Percentages where the school shows them; a grades-only student has
        # a grade instead, and is counted as a result all the same.
        averages = [row["average_percentage"] for row in rows if row["average_percentage"] is not None]
        gpas = [float(row["gpa"]) for row in rows if row["gpa"] is not None]
        totals = {
            "students": len(rows),
            "students_with_a_result": sum(1 for row in rows if row["average_percentage"] is not None or row["grade"]),
            "tests_held": tests_held,
            "absent": sum(row["absent"] for row in rows),
            "average_percentage": percent(sum(float(value) for value in averages) / len(averages)) if averages else None,
            # Under the school's weak line - or, graded "grades only", on a
            # failing grade.
            "students_below_the_mark": behind,
        }

        # Only where somebody is graded by points.
        if gpas:
            totals["average_gpa"] = php_number(round(sum(gpas) / len(gpas), 2))
            totals["students_with_a_gpa"] = len(gpas)

        return totals

    @staticmethod
    def _weak(per_subject: dict, threshold, scale) -> int | None:
        """How many of this student's subjects are under the school's mark
        (nothing at all where it keeps none) - or, graded "grades only", on
        a failing grade."""
        if kind_of(scale) == GradeScaleKind.GRADES:
            return sum(1 for value in per_subject.values() if failing(scale, value))

        if threshold is None:
            return None

        return sum(1 for value in per_subject.values() if value is not None and float(value) < threshold)

    @staticmethod
    def _section_of(student: Student) -> str | None:
        section = student.class_section

        return None if section is None else f"{section.school_class.name} {section.name}"

    @staticmethod
    def _attendance(report_range: ReportRange, student_ids: list) -> dict:
        """Each student's attendance over the same period, out of the days
        the school actually ran - the same holiday-aware denominator every
        other report uses."""
        if not student_ids:
            return {}

        marks = Attendance.objects.filter(
            student_id__in=student_ids,
            attendance_date__gte=report_range.start,
            attendance_date__lte=report_range.end,
        )
        present = dict(
            marks.filter(status=AttendanceStatus.PRESENT)
            .order_by()
            .values("student_id")
            .annotate(days=Count("id"))
            .values_list("student_id", "days")
        )
        # A student on a register that was taken but never present is 0%,
        # not "-": the dash is for a student nobody ever marked.
        marked = set(marks.order_by().values_list("student_id", flat=True).distinct())

        return {
            student_id: php_number(report_range.rate(present.get(student_id, 0))) for student_id in marked
        }


class ClassPerformanceReport:
    """One line per class and subject: how the subject went, and for how
    many it is going badly."""

    TITLE = "Class performance by subject"
    PDF_NOTE = (
        "Only published results are counted, and an absentee leaves the average rather than scoring nought. "
        "A subject's average is over every mark in it."
    )
    COMPARED_ROWS = [("average_percentage", "Average %")]
    DEFAULT_PERIOD = "term"

    @staticmethod
    def row_key(row: dict):
        return (row["class_section_id"], row["subject_id"])

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        marks = list(published_marks(report_range, filters))
        threshold = weak_below(report_range.school_id)
        scales = Scales(report_range.school_id, marks)

        counted: dict[tuple, dict] = {}

        for mark in marks:
            assessment = mark.assessment
            key = (assessment.class_section_id, assessment.subject_id)
            entry = counted.setdefault(key, {
                "assessment": assessment,
                "assessment_ids": set(),
                "students": {},
                "marks": [],
                "absent": 0,
                "rows": [],
            })

            entry["assessment_ids"].add(assessment.id)
            entry["rows"].append(mark)

            if mark.is_absent:
                entry["absent"] += 1
                entry["students"].setdefault(mark.student_id, [])
                continue

            percentage = percentage_of(mark)

            if percentage is None:
                continue

            entry["marks"].append(percentage)
            entry["students"].setdefault(mark.student_id, []).append(percentage)

        sections = self._sections(key[0] for key in counted)
        rows = []
        below_of: dict[tuple, set] = {}

        for (section_id, subject_id), entry in counted.items():
            assessment = entry["assessment"]
            average = mean_of(entry["marks"])
            per_student = {
                student: mean_of(values) for student, values in entry["students"].items() if values
            }
            scale = scales.of(entry["rows"])
            kind = kind_of(scale)
            grades_only = kind == GradeScaleKind.GRADES

            if grades_only:
                # A failing grade, the line a grades-only school reads.
                below = {student for student, value in per_student.items() if failing(scale, value)}
            else:
                below = (
                    None if threshold is None
                    else {student for student, value in per_student.items() if float(value) < threshold}
                )
            below_of[(section_id, subject_id)] = below or set()
            band = band_of(scale, average)

            rows.append({
                "class_section_id": section_id,
                "class_section": sections.get(section_id, (None,))[0],
                "subject_id": subject_id,
                "subject": assessment.subject.name,
                "department": assessment.subject.department.name if assessment.subject.department_id else None,
                "students": len(entry["students"]),
                "assessments": len(entry["assessment_ids"]),
                "marks_counted": len(entry["marks"]),
                "absent": entry["absent"],
                # Grades only: no marks or percentages shown, the grade is
                # the figure (docs/document-styles.md).
                "average_percentage": None if grades_only else percent(average),
                "highest_percentage": None if grades_only or not entry["marks"] else percent(max(entry["marks"])),
                "lowest_percentage": None if grades_only or not entry["marks"] else percent(min(entry["marks"])),
                "grade": None if band is None else band.label,
                # The mean of the students' grade points in the subject, on
                # a GPA scale only.
                "average_points": points_mean(scale, per_student.values()),
                "students_below_the_mark": None if below is None else len(below),
                "grading": kind,
            })

        if filters.get("below") is not None:
            limit = float(filters["below"])
            rows = [
                row for row in rows
                if row["average_percentage"] is not None and float(row["average_percentage"]) < limit
            ]

        rows.sort(key=lambda row: (
            sections.get(row["class_section_id"], (None, (10**6, "", "")))[1], row["subject"] or "", row["subject_id"],
        ))

        # Each student once, however many subjects they are behind in - the
        # lines' own counts added up counted one student once per subject.
        behind = set().union(*(below_of[(row["class_section_id"], row["subject_id"])] for row in rows)) if rows else set()

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": self._totals(rows, None if threshold is None else len(behind)),
        }

    def headings(self) -> list[str]:
        return [
            "Class", "Subject", "Department", "Students", "Tests", "Marks counted", "Absent", "Average %",
            "Grade", "Average points", "Highest %", "Lowest %", "Students below the mark",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["class_section"], row["subject"], row["department"], row["students"], row["assessments"],
                row["marks_counted"], row["absent"], row["average_percentage"], row["grade"], row["average_points"],
                row["highest_percentage"], row["lowest_percentage"], row["students_below_the_mark"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(totals[key] for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "classes_and_subjects": total("classes_and_subjects"),
            "assessments": total("assessments"),
            "marks_counted": total("marks_counted"),
            "absent": total("absent"),
            # Weighted by the marks each branch counted, so a big branch
            # carries more of the group's average than a small one.
            "average_percentage": combined_average(branch_totals, "marks_counted", "average_percentage"),
            "students_below_in_a_subject": sum(totals["students_below_in_a_subject"] or 0 for totals in branch_totals),
        }

    @staticmethod
    def _totals(rows: list[dict], behind: int | None) -> dict:
        counted = sum(row["marks_counted"] for row in rows)
        # Over the rows that show a percentage: a grades-only class has none,
        # and counting its marks with no percentage made the school's
        # average read 0% when every class was graded that way.
        with_percentage = [row for row in rows if row["average_percentage"] is not None]
        weighted = sum(float(row["average_percentage"]) * row["marks_counted"] for row in with_percentage)
        weighed = sum(row["marks_counted"] for row in with_percentage)

        return {
            "classes_and_subjects": len(rows),
            "assessments": sum(row["assessments"] for row in rows),
            "marks_counted": counted,
            "absent": sum(row["absent"] for row in rows),
            # Over every mark, not a mean of the subject means: a subject
            # with forty marks should weigh more than one with four.
            "average_percentage": percent(weighted / weighed) if weighed else None,
            # Students under the school's mark in at least one subject, each
            # once; nothing at all where the school keeps no mark.
            "students_below_in_a_subject": behind,
        }

    @staticmethod
    def _sections(section_ids) -> dict:
        sections = ClassSection.objects.filter(id__in=set(section_ids)).select_related("school_class")

        # Its name, and where it sorts (class_order).
        return {
            section.id: (f"{section.school_class.name} {section.name}", class_order(section)) for section in sections
        }
