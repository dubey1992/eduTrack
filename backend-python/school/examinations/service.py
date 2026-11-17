"""Examinations and admit cards (docs/examinations.md, decided 2026-11-17).

An exam belongs to one academic year of one school. Its date sheet is a set
of papers - a subject for a class on a day, from a start to an end time, in
the school's own wall-clock time. Nothing here is an instant: a paper at 9
in Lucknow is at 9 on the card wherever the server runs.

**A card is only ever printed from a published version.** Publishing freezes
the exam and its date sheet as JSON (`examination_versions`) and bumps the
version; a change made after that is a draft until it is published again,
and the card then reads "Version 2". A school can reprint an older version
exactly as it was issued.

**Whether a student gets a card** (`card_state`) is decided here, on the
server, for every reader alike:

1. the exam has been published - else `not_published`;
2. the student's class that year sits at least one paper - else `no_papers`;
3. the school has not withheld it by name - else `withheld`, with the
   reason staff read and a parent never does;
4. when the exam holds cards for overdue fees, the student owes nothing
   overdue - unless the school let them through by name ("allow"). Else
   `fee_hold`.

Nothing else holds a card: no attendance rule, no marks rule. Those would be
policies the school has not made.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import DecimalField, F, Q, Sum
from django.utils import timezone

from .. import audit, dates
from ..enums import FeeDueStatus, StudentStatus
from ..errors import AdmitCardUnavailable, ExaminationNotDraftable
from ..models import (
    Examination,
    ExaminationException,
    ExaminationPaper,
    ExaminationVersion,
    SchoolClass,
    Student,
    StudentEnrollment,
    StudentFeeDue,
)

MODULE = "examinations"
DRAFT = "draft"
PUBLISHED = "published"
STYLES = ("classic", "mono")
WITHHOLD = "withhold"
ALLOW = "allow"
OPEN = (FeeDueStatus.PENDING, FeeDueStatus.PARTIAL)
MONEY = DecimalField(max_digits=14, decimal_places=2)

# What a card's state says, to staff and to a parent. A parent never reads a
# withheld card's reason: that is the school's to explain.
STATE_WORDS = {
    "ready": "Ready",
    "not_published": "Not published yet",
    "no_papers": "No papers for this class",
    "withheld": "Withheld by the school",
    "fee_hold": "Held: fees overdue",
}
PARENT_WORDS = {
    "ready": "Your child's admit card is ready.",
    "not_published": "The school has not published the admit cards yet.",
    "no_papers": "Your child's class has no paper in this exam.",
    "withheld": "This admit card is not available. Please contact the school.",
    "fee_hold": "This admit card is held while fees are overdue. Please contact the school office.",
}


def hhmm(value: dt.time | None) -> str | None:
    return None if value is None else value.strftime("%H:%M")


def time_label(value: str | None) -> str:
    """"09:00" -> "9:00 AM", the way the rest of the app writes a time."""
    if not value:
        return ""

    hour, minute = (int(part) for part in value.split(":")[:2])

    return f"{hour % 12 or 12}:{minute:02d} {'AM' if hour < 12 else 'PM'}"


def date_label(value: str) -> str:
    """"2026-12-07" -> "Mon 12/07/2026": the app's one date order, with the
    day of the week a family plans by."""
    day = dt.date.fromisoformat(value)

    return f"{day.strftime('%A')[:3]} {dates.us(day)}"


# -- the frozen version -------------------------------------------------------------------


def snapshot_of(exam: Examination) -> dict:
    """The exam and its date sheet as a card reads them - what a publish
    freezes. Papers sorted by date, then time, then subject; classes by
    level, so two snapshots of the same sheet are equal."""
    papers = (
        ExaminationPaper.objects.filter(examination_id=exam.id)
        .select_related("school_class", "subject")
        .order_by("school_class__level", "school_class__name", "exam_date", "start_time", "subject__name")
    )
    classes: dict[str, dict] = {}

    for paper in papers:
        entry = classes.setdefault(str(paper.school_class_id), {"name": paper.school_class.name, "papers": []})
        entry["papers"].append({
            "subject": paper.subject.name,
            "date": paper.exam_date.isoformat(),
            "start": hhmm(paper.start_time),
            "end": hhmm(paper.end_time),
        })

    return {
        "name": exam.name,
        "year": exam.academic_year.name,
        "term": exam.academic_term.name if exam.academic_term_id else None,
        "centre": exam.centre or None,
        "reporting_time": hhmm(exam.reporting_time),
        "instructions": [line.strip() for line in (exam.instructions or "").splitlines() if line.strip()],
        "card_style": exam.card_style,
        "classes": classes,
    }


def latest_version(exam: Examination) -> ExaminationVersion | None:
    return ExaminationVersion.objects.filter(examination_id=exam.id).order_by("-version").first()


def has_unpublished_changes(exam: Examination) -> bool:
    """Whether the exam differs from what was last issued. A draft that was
    never published is all unpublished change."""
    latest = latest_version(exam)

    return latest is None or latest.snapshot != snapshot_of(exam)


# -- the card's state ----------------------------------------------------------------------


@dataclass(frozen=True)
class CardState:
    code: str
    reason: str | None = None
    overdue: Decimal | None = None

    @property
    def ready(self) -> bool:
        return self.code == "ready"


def class_of(student: Student, year_id: int) -> int | None:
    """The student's class in the exam's year: the enrollment that year, or
    their section today when it belongs to that year."""
    enrollment = StudentEnrollment.objects.filter(student_id=student.id, academic_year_id=year_id).first()

    if enrollment is not None:
        return enrollment.school_class_id

    section = student.class_section

    if section is not None and section.school_class.academic_year_id == year_id:
        return section.school_class_id

    return None


def overdue_by_student(student_ids, today: dt.date) -> dict[int, Decimal]:
    """What each student owes on dues past their date, in one query."""
    rows = (
        StudentFeeDue.objects.filter(student_id__in=list(student_ids), status__in=OPEN, due_date__lt=today)
        .filter(amount__gt=F("discount_amount") + F("paid_amount"))
        .values("student_id")
        .annotate(owed=Sum(F("amount") - F("discount_amount") - F("paid_amount"), output_field=MONEY))
    )

    return {row["student_id"]: row["owed"] for row in rows}


def state_for(exam: Examination, version: ExaminationVersion | None, class_id: int | None, exception,
              overdue: Decimal | None) -> CardState:
    """The rules, with everything they read already fetched - one student
    or a class list."""
    if version is None:
        return CardState("not_published")

    if class_id is None or str(class_id) not in version.snapshot["classes"]:
        return CardState("no_papers")

    if exception is not None and exception.kind == WITHHOLD:
        return CardState("withheld", reason=exception.reason)

    allowed = exception is not None and exception.kind == ALLOW

    if exam.block_on_fee_dues and overdue and overdue > 0 and not allowed:
        return CardState("fee_hold", overdue=overdue)

    return CardState("ready")


def card_state(exam: Examination, student: Student, today: dt.date) -> CardState:
    exception = ExaminationException.objects.filter(examination_id=exam.id, student_id=student.id).first()
    overdue = overdue_by_student([student.id], today).get(student.id) if exam.block_on_fee_dues else None

    return state_for(exam, latest_version(exam), class_of(student, exam.academic_year_id), exception, overdue)


# -- the exam itself -------------------------------------------------------------------


class ExaminationService:
    @staticmethod
    def create(data: dict, actor) -> Examination:
        now = timezone.now()
        year = data["academic_year"]

        try:
            with transaction.atomic():
                exam = Examination.objects.create(
                    school_id=year.school_id, academic_year_id=year.id, academic_term=data.get("academic_term"),
                    name=data["name"], centre=data.get("centre"), reporting_time=data.get("reporting_time"),
                    instructions=data.get("instructions"), card_style=data.get("card_style") or "classic",
                    block_on_fee_dues=bool(data.get("block_on_fee_dues")), status=DRAFT, version=0,
                    created_by_id=getattr(actor, "id", None), created_at=now, updated_at=now,
                )
                audit.record(
                    actor=actor, action="examination.created", module=MODULE, entity_type="examination",
                    entity_id=exam.id, school_id=exam.school_id, new={"name": exam.name},
                )
        except IntegrityError:
            from rest_framework import serializers

            raise serializers.ValidationError({"name": ["This year already has an exam with this name."]})

        return exam

    FIELDS = ("name", "academic_term", "centre", "reporting_time", "instructions", "card_style", "block_on_fee_dues")

    @classmethod
    def update(cls, exam: Examination, data: dict, actor) -> Examination:
        before = {"name": exam.name, "centre": exam.centre, "block_on_fee_dues": exam.block_on_fee_dues}

        for field in cls.FIELDS:
            if field in data:
                setattr(exam, field, data[field])

        exam.updated_at = timezone.now()

        try:
            with transaction.atomic():
                exam.save()
                audit.record(
                    actor=actor, action="examination.updated", module=MODULE, entity_type="examination",
                    entity_id=exam.id, school_id=exam.school_id, old=before,
                    new={"name": exam.name, "centre": exam.centre, "block_on_fee_dues": exam.block_on_fee_dues},
                )
        except IntegrityError:
            from rest_framework import serializers

            raise serializers.ValidationError({"name": ["This year already has an exam with this name."]})

        return exam

    @staticmethod
    def delete(exam: Examination, actor) -> None:
        """Only an exam that was never published: a published one has issued
        cards, and those stay a record of what the school handed out."""
        if exam.version > 0:
            raise ExaminationNotDraftable("This exam has been published. Its admit cards stay on record.")

        with transaction.atomic():
            ExaminationPaper.objects.filter(examination_id=exam.id).delete()
            ExaminationException.objects.filter(examination_id=exam.id).delete()
            audit.record(
                actor=actor, action="examination.deleted", module=MODULE, entity_type="examination",
                entity_id=exam.id, school_id=exam.school_id, old={"name": exam.name},
            )
            exam.delete()

    @staticmethod
    def set_papers(exam: Examination, papers: list[dict], actor) -> None:
        """Replaces the whole date sheet, as the screen edits it. Checked by
        the request; written here in one transaction."""
        now = timezone.now()

        with transaction.atomic():
            ExaminationPaper.objects.filter(examination_id=exam.id).delete()
            ExaminationPaper.objects.bulk_create([
                ExaminationPaper(
                    examination_id=exam.id, school_class_id=paper["school_class"].id,
                    subject_id=paper["subject"].id, exam_date=paper["exam_date"], start_time=paper["start_time"],
                    end_time=paper["end_time"], created_at=now, updated_at=now,
                )
                for paper in papers
            ])
            Examination.objects.filter(pk=exam.id).update(updated_at=now)
            audit.record(
                actor=actor, action="examination.papers_saved", module=MODULE, entity_type="examination",
                entity_id=exam.id, school_id=exam.school_id, new={"papers": len(papers)},
            )

    @staticmethod
    def publish(exam: Examination, actor) -> Examination:
        """Freezes what the cards will say as the next version."""
        with transaction.atomic():
            # Only the exam's own row is locked: the term is a nullable join,
            # and Postgres will not lock that side of one.
            exam = Examination.objects.select_for_update(of=("self",)).select_related(
                "academic_year", "academic_term"
            ).get(pk=exam.id)
            snapshot = snapshot_of(exam)

            if not snapshot["classes"]:
                raise ExaminationNotDraftable("Add at least one paper to the date sheet before publishing.")

            latest = latest_version(exam)

            if latest is not None and latest.snapshot == snapshot:
                raise ExaminationNotDraftable(f"Nothing has changed since version {latest.version} was published.")

            now = timezone.now()
            exam.version += 1
            exam.status = PUBLISHED
            exam.published_at = now
            exam.published_by_id = getattr(actor, "id", None)
            exam.updated_at = now
            exam.save(update_fields=["version", "status", "published_at", "published_by", "updated_at"])
            ExaminationVersion.objects.create(
                examination_id=exam.id, version=exam.version, snapshot=snapshot, published_at=now,
                published_by_id=getattr(actor, "id", None), created_at=now, updated_at=now,
            )
            audit.record(
                actor=actor, action="examination.published", module=MODULE, entity_type="examination",
                entity_id=exam.id, school_id=exam.school_id,
                new={"version": exam.version, "classes": len(snapshot["classes"])},
            )

        return exam

    @staticmethod
    def set_exception(exam: Examination, student: Student, kind: str | None, reason: str | None, actor) -> None:
        """Withhold a card, let one through a fee hold, or (kind None) go back
        to the rules."""
        now = timezone.now()
        old = ExaminationException.objects.filter(examination_id=exam.id, student_id=student.id).first()

        with transaction.atomic():
            if kind is None:
                if old is not None:
                    old.delete()
            elif old is None:
                ExaminationException.objects.create(
                    examination_id=exam.id, student_id=student.id, kind=kind, reason=reason,
                    created_by_id=getattr(actor, "id", None), created_at=now, updated_at=now,
                )
            else:
                ExaminationException.objects.filter(pk=old.pk).update(
                    kind=kind, reason=reason, created_by_id=getattr(actor, "id", None), updated_at=now,
                )

            audit.record(
                actor=actor, action="examination.card_exception", module=MODULE, entity_type="student",
                entity_id=student.id, school_id=exam.school_id,
                old={"kind": old.kind if old else None}, new={"kind": kind, "examination_id": exam.id},
            )


# -- who sits it ----------------------------------------------------------------------------


def candidates(exam: Examination, *, school_class_id=None, class_section_id=None, q: str = ""):
    """The students of the exam's year in the classes its date sheet covers,
    ordered by class, section, roll number and name. Read by enrollment, so a
    student who moved class mid-year is listed under the class they sit in."""
    class_ids = set(
        ExaminationPaper.objects.filter(examination_id=exam.id).values_list("school_class_id", flat=True)
    )
    latest = latest_version(exam)

    if latest is not None:
        class_ids |= {int(key) for key in latest.snapshot["classes"]}

    if school_class_id:
        class_ids &= {int(school_class_id)}

    rows = StudentEnrollment.objects.filter(
        academic_year_id=exam.academic_year_id, school_class_id__in=class_ids,
        student__status=StudentStatus.ACTIVE, student__school_id=exam.school_id,
    ).select_related("student", "school_class", "class_section")

    if class_section_id:
        rows = rows.filter(class_section_id=class_section_id)

    if q:
        rows = rows.filter(
            Q(student__first_name__icontains=q) | Q(student__last_name__icontains=q)
            | Q(student__admission_number__icontains=q)
        )

    return rows.order_by("school_class__level", "class_section__name", "roll_number", "student__first_name", "id")


def states_for(exam: Examination, enrollments, today: dt.date) -> dict[int, CardState]:
    """Every listed student's card state, in a fixed number of queries."""
    student_ids = [row.student_id for row in enrollments]
    exceptions = {
        row.student_id: row
        for row in ExaminationException.objects.filter(examination_id=exam.id, student_id__in=student_ids)
    }
    overdue = overdue_by_student(student_ids, today) if exam.block_on_fee_dues else {}
    latest = latest_version(exam)

    return {
        row.student_id: state_for(exam, latest, row.school_class_id, exceptions.get(row.student_id),
                                  overdue.get(row.student_id))
        for row in enrollments
    }


def require_ready(state: CardState) -> None:
    if not state.ready:
        raise AdmitCardUnavailable(STATE_WORDS[state.code] + ".")


def classes_of(exam: Examination):
    return SchoolClass.objects.filter(
        pk__in=ExaminationPaper.objects.filter(examination_id=exam.id).values("school_class_id")
    ).order_by("level", "name")
