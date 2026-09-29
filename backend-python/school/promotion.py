"""Moving a class into the next year (docs/promotion.md).

This slice is the **preview** and nothing else: it reads a section, works out
what would happen to each student, and writes not one row. The run, its batch
record and the four outcomes come next, and they will use the same defaults
worked out here - which is why the defaults live in a service rather than in
the screen that shows them.

Three ideas carry the whole thing:

- **A default is not a decision.** Everybody active defaults to promoted,
  everybody inactive to left out, and a class with nowhere above it to
  graduated. Nothing is ever defaulted to retained: holding a child back is a
  decision a person makes, so the preview can *suggest* it beside the marks
  that prompted the thought, and the administrator does the rest.
- **A student who cannot be promoted is blocked, not defaulted.** Somebody
  already enrolled in the target year - promoted once already, or admitted
  straight into it - is listed with the reason, because a roster that quietly
  omits a child is how a child gets left behind.
- **The target is suggested, never assumed.** The class one level up in the
  target year, with the same section name where there is one. A school whose
  sections do not line up picks its own, and a class with nothing above it is
  the graduating case rather than an error.
"""

from __future__ import annotations

import decimal

from django.db.models import Avg, Count, DecimalField, ExpressionWrapper, F

from . import modules
from .clock import SchoolClock
from .enums import AssessmentStatus, AttendanceStatus, StudentStatus, UserRole
from .errors import SameAcademicYear, TargetSectionMismatch, TargetYearNotFound
from .models import (
    AcademicTerm,
    AcademicYear,
    Assessment,
    AssessmentMark,
    Attendance,
    ClassSection,
    SchoolClass,
    Student,
    StudentEnrollment,
)
from .reports.range import ReportRange
from .services import HolidayService, php_number

MODULE = "academics"
ASSESSMENTS = "assessments"

# What the screen offers per student. Kept as strings rather than an enum
# because they are the *request's* vocabulary, not a column's: the outcome a
# run records (EnrollmentStatus) is past tense - promoted, retained - and
# these are the instruction.
PROMOTE = "promote"
RETAIN = "retain"
GRADUATE = "graduate"
LEAVE = "leave"

NOTHING_TO_PROMOTE = "NOTHING_TO_PROMOTE"


def school_id_of(section: ClassSection) -> int:
    """A section belongs to its school through its class - there is no column
    on the section itself, and inventing one here would be a second answer to
    a question the schema already answers."""
    return section.school_class.school_id


class PromotionPreview:
    """What would happen if this section were promoted into that year."""

    @classmethod
    def build(cls, section: ClassSection, to_year: AcademicYear, to_section_id=None) -> dict:
        from_year = section.school_class.academic_year

        if from_year.id == to_year.id:
            raise SameAcademicYear("A class cannot be promoted into the year it is already in.")

        target = cls.resolve_target(section, to_year, to_section_id)
        students = cls.roster(section)
        enrolled = cls.already_enrolled(students, to_year)
        marks = cls.averages(section, from_year)
        attendance = cls.attendance_rates(section, from_year, [student.id for student in students])

        rows = [
            cls.row(student, target, enrolled, marks, attendance)
            for student in students
        ]

        return {
            "from": cls.side(section, from_year),
            "to": {
                "academic_year_id": to_year.id,
                "academic_year_name": to_year.name,
                "class_section_id": None if target["section"] is None else target["section"].id,
                "class_section_name": cls.section_name(target["section"]),
                "school_class_id": None if target["school_class"] is None else target["school_class"].id,
                "school_class_name": None if target["school_class"] is None else target["school_class"].name,
                # True when the school did not name one and this is the
                # backend's guess, which the screen says out loud.
                "is_suggested": target["is_suggested"],
            },
            # No class above this one: the year ends here, so everybody
            # leaves the school rather than moving up.
            "is_graduating": target["school_class"] is None,
            "can_run": bool(rows) and any(not row["is_blocked"] for row in rows),
            "cannot_run_reason": None if rows else NOTHING_TO_PROMOTE,
            "suggestions": marks["meta"],
            "counts": cls.counts(rows),
            "students": rows,
        }

    # -- the two sides ------------------------------------------------------

    @staticmethod
    def side(section: ClassSection, year: AcademicYear) -> dict:
        return {
            "academic_year_id": year.id,
            "academic_year_name": year.name,
            "class_section_id": section.id,
            "class_section_name": PromotionPreview.section_name(section),
            "school_class_id": section.school_class_id,
            "school_class_name": section.school_class.name,
            "level": section.school_class.level,
        }

    @staticmethod
    def section_name(section: ClassSection | None) -> str | None:
        if section is None:
            return None

        return f"{section.school_class.name} {section.name}".strip()

    @classmethod
    def resolve_target(cls, section: ClassSection, to_year: AcademicYear, to_section_id) -> dict:
        """The section the students would land in.

        Named by the school, or suggested: the class one level up in the
        target year, and within it the section of the same name where there
        is one. A named section must belong to the target year and the same
        school - anything else is a request to move children into somebody
        else's class, and it is refused by code rather than silently ignored.
        """
        if to_section_id is not None:
            target = (
                ClassSection.objects.select_related("school_class")
                .filter(
                    pk=to_section_id,
                    school_class__academic_year_id=to_year.id,
                    school_class__school_id=school_id_of(section),
                )
                .first()
            )

            if target is None:
                raise TargetSectionMismatch("Choose a section that belongs to the year you are promoting into.")

            return {"section": target, "school_class": target.school_class, "is_suggested": False}

        next_class = SchoolClass.objects.filter(
            school_id=school_id_of(section), academic_year_id=to_year.id, level=section.school_class.level + 1
        ).first()

        if next_class is None:
            return {"section": None, "school_class": None, "is_suggested": True}

        sections = ClassSection.objects.select_related("school_class").filter(school_class_id=next_class.id)
        suggested = sections.filter(name=section.name).first() or sections.order_by("name", "id").first()

        return {"section": suggested, "school_class": next_class, "is_suggested": True}

    # -- the roster ---------------------------------------------------------

    @staticmethod
    def roster(section: ClassSection):
        """Who is in the class. A graduated student is not: they finished, and
        offering them a fifth outcome would only invite a mistake."""
        return list(
            Student.objects.filter(class_section_id=section.id)
            .exclude(status=StudentStatus.GRADUATED)
            .order_by("roll_number", "first_name", "last_name", "id")
        )

    @staticmethod
    def already_enrolled(students, to_year: AcademicYear) -> set:
        """Students who already have a row in the target year - promoted once
        already, or admitted straight into the new year."""
        return set(
            StudentEnrollment.objects.filter(
                academic_year_id=to_year.id, student_id__in=[student.id for student in students]
            ).values_list("student_id", flat=True)
        )

    @classmethod
    def row(cls, student: Student, target: dict, enrolled: set, marks: dict, attendance: dict) -> dict:
        blocked = student.id in enrolled
        average = marks["by_student"].get(student.id)

        return {
            "student_id": student.id,
            "name": student.name,
            "admission_number": student.admission_number,
            "roll_number": student.roll_number,
            "status": student.status,
            "default_outcome": cls.default_outcome(student, target),
            "is_blocked": blocked,
            "blocked_reason": (
                f"{student.name} already has a place in this year." if blocked else None
            ),
            "average_percentage": None if average is None else str(average),
            "attendance_percentage": php_number(attendance.get(student.id)),
            "suggested_outcome": RETAIN if cls.below_pass(average, marks["meta"]) else None,
            "suggestion_reason": (
                f"Average {average}% is below the school's {marks['meta']['pass_percentage']}% pass mark."
                if cls.below_pass(average, marks["meta"])
                else None
            ),
        }

    @staticmethod
    def default_outcome(student: Student, target: dict) -> str:
        """Promote, unless the facts say otherwise.

        A student already marked inactive has gone; the year closes for them
        as left out rather than pretending they finished it. A class with
        nothing above it graduates.
        """
        if student.status != StudentStatus.ACTIVE:
            return LEAVE

        return GRADUATE if target["school_class"] is None else PROMOTE

    @staticmethod
    def below_pass(average, meta: dict) -> bool:
        if average is None or not meta["available"]:
            return False

        return average < decimal.Decimal(meta["pass_percentage"])

    @staticmethod
    def counts(rows: list) -> dict:
        return {
            outcome: sum(1 for row in rows if row["default_outcome"] == outcome and not row["is_blocked"])
            for outcome in (PROMOTE, RETAIN, GRADUATE, LEAVE)
        }

    # -- what the year looked like -----------------------------------------

    @classmethod
    def averages(cls, section: ClassSection, from_year: AcademicYear) -> dict:
        """Each student's average over the last term that has published
        results, and the school's pass mark to read it against.

        The last term rather than the whole year, because that is the term a
        promotion decision is actually made on. Absences are left out of the
        average, the way they are everywhere else: a child who missed a test
        did not score zero on it.
        """
        meta = {"available": False, "term_id": None, "term_name": None, "pass_percentage": None}

        if not modules.is_enabled(school_id_of(section), ASSESSMENTS):
            return {"by_student": {}, "meta": meta}

        published = Assessment.objects.filter(
            class_section_id=section.id, academic_year_id=from_year.id, status=AssessmentStatus.PUBLISHED
        )
        term_id = (
            published.order_by("-academic_term__sequence_number", "-academic_term_id")
            .values_list("academic_term_id", flat=True)
            .first()
        )

        if term_id is None:
            return {"by_student": {}, "meta": meta}

        percentage = ExpressionWrapper(
            F("marks_obtained") * 100 / F("assessment__max_marks"),
            output_field=DecimalField(max_digits=8, decimal_places=2),
        )
        averages = (
            AssessmentMark.objects.filter(
                assessment__in=published.filter(academic_term_id=term_id), is_absent=False, marks_obtained__isnull=False
            )
            .values("student_id")
            .annotate(average=Avg(percentage))
        )

        term = AcademicTerm.objects.filter(pk=term_id).first()
        meta = {
            "available": True,
            "term_id": term_id,
            "term_name": None if term is None else term.name,
            "pass_percentage": str(modules.setting(school_id_of(section), ASSESSMENTS, "pass_percentage")),
        }

        return {
            "by_student": {
                row["student_id"]: row["average"].quantize(decimal.Decimal("0.01")) for row in averages
            },
            "meta": meta,
        }

    @staticmethod
    def attendance_rates(section: ClassSection, from_year: AcademicYear, student_ids: list) -> dict:
        """Attendance for the year so far, out of the school's working days -
        the same denominator the attendance report uses, so the two agree."""
        if not student_ids:
            return {}

        today = SchoolClock.for_school(school_id_of(section)).now().date()
        start = from_year.start_date
        # Days that have not happened are not days anybody was absent for.
        end = min(from_year.end_date, today)

        if end < start:
            return {}

        report_range = ReportRange(
            school_id_of(section), start, end, HolidayService.working_dates(school_id_of(section), start, end)
        )
        present = (
            Attendance.objects.filter(
                student_id__in=student_ids,
                attendance_date__range=(start, end),
                status=AttendanceStatus.PRESENT,
            )
            .values("student_id")
            .annotate(days=Count("id"))
        )

        days = {row["student_id"]: row["days"] for row in present}

        # Everybody gets a figure, not only the students with a mark: a child
        # nobody ever marked present was present on none of the days the
        # school ran, and "0%" is the truth where a blank would read as "no
        # data". The rate itself is None only when the year holds no working
        # day at all, which is the report's rule too.
        return {student_id: report_range.rate(days.get(student_id, 0)) for student_id in student_ids}


def target_year(section: ClassSection, to_academic_year_id: int) -> AcademicYear:
    """The year being promoted into, inside the source section's own school.

    A year id from the client is not trusted to belong anywhere: another
    school's year is "not found" rather than a year this school may use.
    """
    year = AcademicYear.objects.filter(pk=to_academic_year_id, school_id=school_id_of(section)).first()

    if year is None:
        raise TargetYearNotFound("Choose an academic year that belongs to this school.")

    return year


def preview(section: ClassSection, to_academic_year_id: int, to_class_section_id=None) -> dict:
    return PromotionPreview.build(section, target_year(section, to_academic_year_id), to_class_section_id)
