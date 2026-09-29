"""What one student's marks add up to (docs/assessments.md).

Computed, never stored. There is no summary table in the product and there
is not one here: every figure below is worked out from published marks and
the register when somebody asks, so a corrected mark or a reopened result
changes the answer immediately rather than leaving a stale row behind.

Four ideas carry it:

- **A draft counts for nothing.** Only a published result is anybody's
  business, so only published assessments are read.
- **Absent is not zero.** An absentee leaves the average's denominator, the
  way they do everywhere else in the product. A subject where the student
  was absent for everything has no average at all - not a nought.
- **The class average is over the same assessments.** "72% against a class
  average of 65%" only means something when both figures describe the same
  tests, so the class figure is built from the marks of exactly the
  assessments the student was marked in.
- **Nothing is invented.** No term, no published result, no working day -
  each reads as nothing rather than as zero, because a zero here is a
  sentence about a child.
"""

from __future__ import annotations

import datetime as dt
import decimal

from django.db.models import Count, Q, Sum

from . import insights, modules
from .clock import SchoolClock
from .enums import AssessmentStatus, AttendanceStatus
from .models import AcademicTerm, Assessment, AssessmentMark, Attendance, GradeScale, Student
from .reports.range import ReportRange
from .services import GradeScaleService, HolidayService, php_number

MODULE = "assessments"

CENT = decimal.Decimal("0.01")


def terms_of(student: Student):
    """Every term of the year the student is in, newest first.

    The year comes from the student's own section rather than from the
    school's current year: a student's page is about them, and after a
    promotion those are the same thing anyway.
    """
    section = student.class_section

    if section is None:
        return AcademicTerm.objects.none()

    return AcademicTerm.objects.filter(academic_year_id=section.school_class.academic_year_id).order_by(
        "-sequence_number", "-start_date"
    )


def default_term(student: Student, today: dt.date) -> AcademicTerm | None:
    """The term a page opens on: the one being lived, and otherwise the last
    one that finished - never an empty future term."""
    terms = list(terms_of(student))

    if not terms:
        return None

    current = [term for term in terms if term.start_date <= today <= term.end_date]

    if current:
        return current[0]

    past = [term for term in terms if term.end_date < today]

    return past[0] if past else terms[-1]


def previous_term(term: AcademicTerm) -> AcademicTerm | None:
    """The term before this one, in the same year."""
    return (
        AcademicTerm.objects.filter(
            academic_year_id=term.academic_year_id, sequence_number__lt=term.sequence_number
        )
        .order_by("-sequence_number")
        .first()
    )


def published_marks(student: Student, term: AcademicTerm):
    """This student's marks in that term's published tests.

    Read by student rather than by section on purpose: a child who changed
    section mid-term, or who was promoted between the two terms being
    compared, keeps every mark they earned (docs/promotion.md).
    """
    return (
        AssessmentMark.objects.filter(
            student_id=student.id,
            assessment__academic_term_id=term.id,
            assessment__status=AssessmentStatus.PUBLISHED,
        )
        .select_related("assessment__subject")
        .order_by("assessment__subject__name", "assessment__assessment_date", "assessment_id")
    )


def percentage_of(mark) -> decimal.Decimal | None:
    """One mark as a percentage, or nothing where the question does not
    arise: absent, unmarked, or a test out of nothing."""
    assessment = mark.assessment

    if mark.is_absent or mark.marks_obtained is None or not assessment.max_marks:
        return None

    return (mark.marks_obtained / assessment.max_marks * 100).quantize(CENT)


def average_of(rows: list[tuple]) -> decimal.Decimal | None:
    """The mean of (percentage, weightage) pairs.

    Weighted only when every test counted carries a weightage, and then
    normalised by the weights actually present - a term whose weightages add
    up to 80 is a school part-way through setting them, not a reason to
    divide by 100 and report everybody as failing. Mixed weightages and
    blanks fall back to a plain mean, because half a weighting is not a
    weighting.
    """
    if not rows:
        return None

    weights = [weight for _, weight in rows]

    if all(weight is not None and weight > 0 for weight in weights):
        total = sum(weights)

        return (sum(value * weight for value, weight in rows) / total).quantize(CENT)

    return (sum(value for value, _ in rows) / len(rows)).quantize(CENT)


def change_between(now, before) -> decimal.Decimal | None:
    if now is None or before is None:
        return None

    return (now - before).quantize(CENT)


class StudentPerformance:
    """One student, one term."""

    @classmethod
    def build(cls, student: Student, term: AcademicTerm | None, today: dt.date) -> dict:
        previous = None if term is None else previous_term(term)

        subjects = [] if term is None else cls.subjects(student, term, previous)

        payload = {
            "student": {
                "id": student.id,
                "name": student.name,
                "admission_number": student.admission_number,
                "class_section_name": cls.section_name(student),
            },
            "term": cls.term_resource(term),
            "previous_term": cls.term_resource(previous),
            "terms": [cls.term_resource(row) for row in terms_of(student)],
            "subjects": subjects,
            "overall": cls.overall(subjects),
            "attendance": cls.attendance(student, term, today),
            # What the screen calls "weak", so the number on the page and the
            # number in the setting are the same number (docs/settings.md).
            "weak_below_percentage": php_number(
                modules.setting(student.school_id, MODULE, "weak_below_percentage")
            ),
        }

        # Read from the figures above rather than from the database: the
        # rules see exactly what the screen shows, so a sentence can never
        # describe numbers the page does not carry (school/insights.py).
        payload["insights"] = insights.for_performance(payload)

        return payload

    @staticmethod
    def section_name(student: Student) -> str | None:
        section = student.class_section

        if section is None:
            return None

        return f"{section.school_class.name} {section.name}".strip()

    @staticmethod
    def term_resource(term: AcademicTerm | None) -> dict | None:
        if term is None:
            return None

        return {
            "id": term.id,
            "name": term.name,
            "sequence_number": term.sequence_number,
            "start_date": term.start_date.isoformat(),
            "end_date": term.end_date.isoformat(),
        }

    # -- the subjects -------------------------------------------------------

    @classmethod
    def subjects(cls, student: Student, term: AcademicTerm, previous: AcademicTerm | None) -> list[dict]:
        rows = list(published_marks(student, term))
        before = cls.averages_by_subject(student, previous) if previous is not None else {}
        scale = cls.grade_scale_for(rows)

        counted: dict[int, dict] = {}

        for mark in rows:
            subject = mark.assessment.subject
            entry = counted.setdefault(
                subject.id,
                {
                    "subject_id": subject.id,
                    "subject_name": subject.name,
                    "assessments": 0,
                    "absent": 0,
                    "marks": [],
                    "assessment_ids": [],
                },
            )

            entry["assessments"] += 1
            entry["assessment_ids"].append(mark.assessment_id)

            if mark.is_absent:
                entry["absent"] += 1
                continue

            percentage = percentage_of(mark)

            if percentage is not None:
                entry["marks"].append((percentage, mark.assessment.weightage))

        class_averages = cls.class_averages(
            [assessment_id for entry in counted.values() for assessment_id in entry["assessment_ids"]]
        )

        subjects = []

        for entry in counted.values():
            average = average_of(entry["marks"])
            was = before.get(entry["subject_id"])

            subjects.append({
                "subject_id": entry["subject_id"],
                "subject_name": entry["subject_name"],
                "assessments": entry["assessments"],
                "absent": entry["absent"],
                "average_percentage": cls.text(average),
                "grade": None if average is None or scale is None else cls.grade(scale, average),
                "class_average_percentage": cls.text(
                    average_of([(class_averages[a], None) for a in entry["assessment_ids"] if a in class_averages])
                ),
                "previous_average_percentage": cls.text(was),
                "change": cls.text(change_between(average, was)),
            })

        return sorted(subjects, key=lambda row: row["subject_name"])

    @classmethod
    def averages_by_subject(cls, student: Student, term: AcademicTerm) -> dict:
        """The same arithmetic for another term, keyed by subject - what
        "are they improving?" is measured against."""
        by_subject: dict[int, list] = {}

        for mark in published_marks(student, term):
            if mark.is_absent:
                continue

            percentage = percentage_of(mark)

            if percentage is not None:
                by_subject.setdefault(mark.assessment.subject_id, []).append(
                    (percentage, mark.assessment.weightage)
                )

        return {subject_id: average_of(rows) for subject_id, rows in by_subject.items()}

    @staticmethod
    def class_averages(assessment_ids: list) -> dict:
        """Each assessment's class average, over everybody who sat it.

        Two queries for the whole page rather than one per test: a subject
        with eight tests would otherwise ask eight times, and a page with six
        subjects forty-eight.
        """
        wanted = set(assessment_ids)

        if not wanted:
            return {}

        totals = dict(Assessment.objects.filter(id__in=wanted).values_list("id", "max_marks"))
        averages = {}

        sat = (
            AssessmentMark.objects.filter(
                assessment_id__in=wanted, is_absent=False, marks_obtained__isnull=False
            )
            .values("assessment_id")
            .annotate(students=Count("id"), total=Sum("marks_obtained"))
        )

        for row in sat:
            maximum = totals.get(row["assessment_id"])

            if not maximum or not row["students"]:
                continue

            mean = row["total"] / row["students"]
            averages[row["assessment_id"]] = (mean / maximum * 100).quantize(CENT)

        return averages

    @staticmethod
    def grade_scale_for(rows) -> GradeScale | None:
        """The scale to read an average against: whichever the term's tests
        used, and otherwise the school's default. A school that grades
        nothing gets no grades, which is a school that reports marks."""
        for mark in rows:
            if mark.assessment.grade_scale_id:
                return GradeScale.objects.prefetch_related("bands").filter(
                    pk=mark.assessment.grade_scale_id
                ).first()

        if not rows:
            return None

        return (
            GradeScale.objects.prefetch_related("bands")
            .filter(school_id=rows[0].assessment.school_id, is_default=True)
            .first()
        )

    @staticmethod
    def grade(scale: GradeScale, average: decimal.Decimal) -> str | None:
        band = GradeScaleService.grade_for(scale, average)

        return None if band is None else band.label

    @staticmethod
    def text(value) -> str | None:
        """Marks travel as strings, the way money does: a client reading
        72.50 as a float would render 72.5 for a figure a school quotes."""
        return None if value is None else str(value)

    # -- the whole term -----------------------------------------------------

    @classmethod
    def overall(cls, subjects: list[dict]) -> dict:
        """The term's own average: every subject's average, evenly.

        Subject by subject rather than mark by mark, so a subject with eight
        tests does not drown one with two - the page reads "how are they
        doing in each subject", and the summary should mean the same thing.
        """
        averages = [decimal.Decimal(row["average_percentage"]) for row in subjects if row["average_percentage"]]
        class_averages = [
            decimal.Decimal(row["class_average_percentage"])
            for row in subjects
            if row["class_average_percentage"]
        ]
        previous = [
            decimal.Decimal(row["previous_average_percentage"])
            for row in subjects
            if row["previous_average_percentage"]
        ]

        average = average_of([(value, None) for value in averages])
        was = average_of([(value, None) for value in previous])

        return {
            "subjects": len(subjects),
            "assessments": sum(row["assessments"] for row in subjects),
            "absent": sum(row["absent"] for row in subjects),
            "average_percentage": cls.text(average),
            "class_average_percentage": cls.text(average_of([(value, None) for value in class_averages])),
            "previous_average_percentage": cls.text(was),
            "change": cls.text(change_between(average, was)),
        }

    # -- the register -------------------------------------------------------

    @staticmethod
    def attendance(student: Student, term: AcademicTerm | None, today: dt.date) -> dict:
        """The same period, out of the school's working days - the holiday
        aware denominator every other attendance figure uses."""
        empty = {
            "working_days": 0,
            "present": 0,
            "absent": 0,
            "leave": 0,
            "not_marked": 0,
            "attendance_rate": None,
        }

        if term is None:
            return empty

        start = term.start_date
        # Days that have not happened are not days anybody was absent for.
        end = min(term.end_date, today)

        if end < start:
            return empty

        report_range = ReportRange(
            student.school_id, start, end, HolidayService.working_dates(student.school_id, start, end)
        )
        counted = Attendance.objects.filter(
            student_id=student.id, attendance_date__range=(start, end)
        ).aggregate(
            present=Count("id", filter=Q(status=AttendanceStatus.PRESENT)),
            absent=Count("id", filter=Q(status=AttendanceStatus.ABSENT)),
            leave=Count("id", filter=Q(status=AttendanceStatus.LEAVE)),
        )
        days = report_range.working_day_count()

        return {
            "working_days": days,
            "present": counted["present"],
            "absent": counted["absent"],
            "leave": counted["leave"],
            # Days nobody marked at all: not an absence, and not a day to
            # count against anybody.
            "not_marked": max(0, days - counted["present"] - counted["absent"] - counted["leave"]),
            "attendance_rate": php_number(report_range.rate(counted["present"])),
        }


def for_student(student: Student, term_id=None) -> dict:
    today = SchoolClock.for_school(student.school_id).now().date()

    if term_id is None:
        term = default_term(student, today)
    else:
        term = AcademicTerm.objects.filter(pk=term_id, school_id=student.school_id).first()

    return StudentPerformance.build(student, term, today)
