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

from django.db import transaction
from django.db.models import Avg, Count, DecimalField, ExpressionWrapper, F, Q
from django.utils import timezone

from . import audit, modules
from .clock import SchoolClock
from .enums import (
    AssessmentStatus,
    AttendanceStatus,
    EnrollmentStatus,
    PromotionOutcome,
    StudentStatus,
    UserRole,
)
from .errors import (
    AlreadyEnrolled,
    NothingToPromote,
    RetainClassMissing,
    RosterChanged,
    SameAcademicYear,
    TargetSectionMismatch,
    TargetYearNotFound,
)
from .models import (
    AcademicTerm,
    AcademicYear,
    Assessment,
    AssessmentMark,
    Attendance,
    ClassSection,
    PromotionBatch,
    SchoolClass,
    Student,
    StudentEnrollment,
    User,
)
from .reports.range import ReportRange
from .scope import SchoolScope
from .services import HolidayService, php_number

MODULE = "academics"
ASSESSMENTS = "assessments"

# What the screen offers per student. The instruction, not the record: what
# a run writes afterwards is EnrollmentStatus, which is past tense.
PROMOTE = PromotionOutcome.PROMOTE
RETAIN = PromotionOutcome.RETAIN
GRADUATE = PromotionOutcome.GRADUATE
LEAVE = PromotionOutcome.LEAVE

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


class PromotionRun:
    """Moving a class into the next year, for real (docs/promotion.md).

    One transaction. The batch row, every closed enrollment, every new one
    and every repointed student commit together or not at all, because a
    half-promoted class is worse than an unpromoted one: nobody could tell by
    looking which children had been moved.

    What each outcome does:

    - **Promoted**: the year closes as `promoted`, a new `studying` row opens
      in the target class, and `students.class_section_id` is repointed.
    - **Retained**: closes as `retained`, and the new row is in the *same*
      class of the new year - repeating a year means repeating it.
    - **Graduated**: closes as `graduated`, no new row, the section pointer
      cleared and the student marked graduated.
    - **Left out**: closes as `left` and nothing else is touched. They had
      already gone, and the year closes honestly rather than pretending they
      finished it.

    The refusals matter as much as the outcomes. A roster that changed since
    the list was drawn up is refused whole rather than promoted stale, and a
    student who already has a place in the target year is named rather than
    skipped - the unique key on (student, year) would stop it anyway, and
    being told which child is the point.
    """

    MODULE = "academic"

    OUTCOME_STATUS = {
        PROMOTE: EnrollmentStatus.PROMOTED,
        RETAIN: EnrollmentStatus.RETAINED,
        GRADUATE: EnrollmentStatus.GRADUATED,
        LEAVE: EnrollmentStatus.LEFT,
    }

    @classmethod
    def run(cls, section: ClassSection, data: dict, actor: User) -> PromotionBatch:
        to_year = target_year(section, data["to_academic_year_id"])
        from_year = section.school_class.academic_year

        if from_year.id == to_year.id:
            raise SameAcademicYear("A class cannot be promoted into the year it is already in.")

        target = PromotionPreview.resolve_target(section, to_year, data.get("to_class_section_id"))
        outcomes = {row["student_id"]: row["outcome"] for row in data["outcomes"]}

        if not outcomes:
            raise NothingToPromote("Say what should happen to each student before running a promotion.")

        now = timezone.now()

        with transaction.atomic():
            students = cls.locked_roster(section)
            # The most specific answer first: running the same batch twice
            # empties the section, and "there is nobody here" would be a
            # true, useless answer to "you already did this".
            cls.check_free(outcomes, to_year)
            cls.check_roster(students, outcomes)

            batch = PromotionBatch.objects.create(
                school_id=school_id_of(section),
                from_academic_year_id=from_year.id,
                to_academic_year_id=to_year.id,
                from_class_section_id=section.id,
                to_class_section_id=None if target["section"] is None else target["section"].id,
                run_by_id=actor.id,
                run_at=now,
                created_at=now,
                updated_at=now,
            )

            counted = {PROMOTE: [], RETAIN: [], GRADUATE: [], LEAVE: []}

            for student in students:
                outcome = outcomes.get(student.id)

                # Not named in the batch: the administrator left them out of
                # this run, and leaving somebody alone is not an error.
                if outcome is None:
                    continue

                cls.apply(student, outcome, section, to_year, target, batch, from_year, now)
                counted[outcome].append(student.id)

            PromotionBatch.objects.filter(pk=batch.id).update(
                promoted_count=len(counted[PROMOTE]),
                retained_count=len(counted[RETAIN]),
                graduated_count=len(counted[GRADUATE]),
                left_count=len(counted[LEAVE]),
                updated_at=now,
            )

            cls._record(batch, section, target, counted)

        return cls.with_names().get(pk=batch.id)

    @staticmethod
    def with_names():
        return PromotionBatch.objects.select_related(
            "from_academic_year",
            "to_academic_year",
            "from_class_section__school_class",
            "to_class_section__school_class",
            "run_by",
        )

    # -- the checks ---------------------------------------------------------

    @staticmethod
    def locked_roster(section: ClassSection):
        """The class as it is right now, held for the length of the run so two
        administrators cannot promote the same children twice."""
        return list(
            Student.objects.select_for_update()
            .filter(class_section_id=section.id)
            .exclude(status=StudentStatus.GRADUATED)
            .order_by("id")
        )

    @staticmethod
    def check_roster(students, outcomes: dict) -> None:
        """The batch must describe the class in front of it.

        Two administrators on two screens, one admits a child while the other
        is reviewing: the run refuses rather than promoting a stale list. A
        student named who is not in the section is the same mistake from the
        other end, and gets the same answer.
        """
        if not students:
            raise NothingToPromote("There is nobody in this class to promote.")

        roster = {student.id for student in students}

        if [student_id for student_id in outcomes if student_id not in roster]:
            raise RosterChanged(
                "This class has changed since the list was drawn up. Review it again before promoting."
            )

    @staticmethod
    def check_free(outcomes: dict, to_year: AcademicYear) -> None:
        """Nobody in the batch may already have a place in the target year."""
        taken = list(
            StudentEnrollment.objects.filter(academic_year_id=to_year.id, student_id__in=list(outcomes))
            .select_related("student")
            .values_list("student__first_name", "student__last_name")[:5]
        )

        if taken:
            names = ", ".join(f"{first} {last}".strip() for first, last in taken)

            raise AlreadyEnrolled(f"Already has a place in {to_year.name}: {names}.")

    # -- one student --------------------------------------------------------

    @classmethod
    def apply(cls, student, outcome, section, to_year, target, batch, from_year, now) -> None:
        closed = cls.close_year(student, section, from_year, outcome, batch, now)

        if outcome == PROMOTE:
            landing = target["section"]

            if landing is None:
                # Nothing above this class, so there is nowhere to promote
                # into. Said by name rather than left to a foreign key.
                raise RetainClassMissing(
                    f"There is no class above {section.school_class.name} in {to_year.name} to promote into."
                )

            cls.open_year(student, landing, to_year, batch, closed, now)
            cls.repoint(student, landing.id, now)

            return

        if outcome == RETAIN:
            landing = cls.same_class_next_year(section, to_year)
            cls.open_year(student, landing, to_year, batch, closed, now)
            cls.repoint(student, landing.id, now)

            return

        if outcome == GRADUATE:
            # They have finished: no new year, no class, and a status that
            # keeps them out of every register and every bus list.
            cls.repoint(student, None, now, status=StudentStatus.GRADUATED)

        # LEAVE repoints nothing. The child had already gone; the year simply
        # closes for them.

    @classmethod
    def close_year(cls, student, section, from_year, outcome, batch, now) -> StudentEnrollment:
        """Writes how this student's year ended, making the row if the
        backfill never did - a year that ends unrecorded would be a hole in
        the history the promotion itself had caused."""
        enrollment, created = StudentEnrollment.objects.update_or_create(
            student_id=student.id,
            academic_year_id=from_year.id,
            defaults={
                "school_id": student.school_id,
                "school_class_id": section.school_class_id,
                "class_section_id": section.id,
                "roll_number": student.roll_number,
                "status": cls.OUTCOME_STATUS[outcome],
                "promotion_batch_id": batch.id,
                "updated_at": now,
            },
        )

        if created:
            StudentEnrollment.objects.filter(pk=enrollment.id).update(created_at=now)

        return enrollment

    @staticmethod
    def open_year(student, landing: ClassSection, to_year, batch, closed, now) -> None:
        StudentEnrollment.objects.create(
            school_id=student.school_id,
            student_id=student.id,
            academic_year_id=to_year.id,
            school_class_id=landing.school_class_id,
            class_section_id=landing.id,
            roll_number=student.roll_number,
            status=EnrollmentStatus.STUDYING,
            promotion_batch_id=batch.id,
            promoted_from_enrollment_id=closed.id,
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def repoint(student, class_section_id, now, status=None) -> None:
        """`students.class_section_id` is the present tense, and a promotion
        changes it here and nowhere else."""
        fields = {"class_section_id": class_section_id, "updated_at": now}

        if status is not None:
            fields["status"] = status

        Student.objects.filter(pk=student.id).update(**fields)

    @staticmethod
    def same_class_next_year(section: ClassSection, to_year: AcademicYear) -> ClassSection:
        """Where a retained child repeats: the same class in the new year, and
        inside it the section of the same name where there is one."""
        same_class = SchoolClass.objects.filter(
            school_id=school_id_of(section), academic_year_id=to_year.id, level=section.school_class.level
        ).first()

        if same_class is None:
            raise RetainClassMissing(
                f"{section.school_class.name} does not exist in {to_year.name}, "
                "so there is nowhere for a retained student to repeat the year."
            )

        sections = ClassSection.objects.filter(school_class_id=same_class.id)
        landing = sections.filter(name=section.name).first() or sections.order_by("name", "id").first()

        if landing is None:
            raise RetainClassMissing(
                f"{same_class.name} in {to_year.name} has no sections, "
                "so there is nowhere for a retained student to repeat the year."
            )

        return landing

    # -- the record ---------------------------------------------------------

    @classmethod
    def _record(cls, batch, section, target, counted: dict) -> None:
        """One entry for the whole run.

        One per student would put forty rows in the log for a single intended
        act and bury everything else, and the enrollment rows already carry
        who ran the batch and when.
        """
        audit.record(
            action="promotion.completed",
            module=cls.MODULE,
            entity_type="PromotionBatch",
            entity_id=batch.id,
            school_id=batch.school_id,
            new={
                "from": PromotionPreview.section_name(section),
                "to": PromotionPreview.section_name(target["section"]),
                "from_academic_year_id": batch.from_academic_year_id,
                "to_academic_year_id": batch.to_academic_year_id,
                "counts": {outcome: len(students) for outcome, students in counted.items()},
                "students": {outcome: students for outcome, students in counted.items() if students},
            },
        )


def run(section: ClassSection, data: dict, actor: User) -> PromotionBatch:
    return PromotionRun.run(section, data, actor)


def history(actor: User, filters: dict):
    """Past runs, newest first - what a school reads to see what was done."""
    batches = SchoolScope.for_actor(actor).apply_to(PromotionRun.with_names(), filters.get("school_id"))

    if filters.get("academic_year_id"):
        # Either side of the move: "what happened to 2026-27" and "what
        # arrived in 2027-28" are the same question asked from two ends.
        batches = batches.filter(
            Q(from_academic_year_id=filters["academic_year_id"])
            | Q(to_academic_year_id=filters["academic_year_id"])
        )

    if filters.get("class_section_id"):
        batches = batches.filter(from_class_section_id=filters["class_section_id"])

    return batches.order_by("-run_at", "-id")


def outcomes_of(batch: PromotionBatch):
    """What the batch did, student by student: the rows it closed, each with
    the year it opened where there was one."""
    return (
        StudentEnrollment.objects.filter(promotion_batch_id=batch.id)
        .exclude(status=EnrollmentStatus.STUDYING)
        .select_related("student", "school_class", "class_section")
        .order_by("student__first_name", "student__last_name", "student_id")
    )


def landing_of(batch: PromotionBatch) -> dict:
    """The new rows the batch opened, keyed by student - so a row can say
    where the child went without a query each."""
    rows = (
        StudentEnrollment.objects.filter(promotion_batch_id=batch.id, status=EnrollmentStatus.STUDYING)
        .select_related("school_class", "class_section")
    )

    return {row.student_id: row for row in rows}
