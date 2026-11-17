"""A parent's note that their child will be away (docs/parent-student-app.md,
F5, decided 2026-11-17).

A parent sends it from the Family app: the days (from today up to 30 days
ahead), a reason, and if they have one a photo of a doctor's note. It never
marks the register. It shows beside the child on the register for each of
its days and arrives in the class teacher's inbox; the teacher - or anyone
who keeps that register - acknowledges it, and the parent sees "Seen by the
class teacher".

The rules a parent meets, each with a sentence they can act on:
- the first day is today or later, the last no more than 30 days ahead, and
  not before the first;
- a reason of 10 to 500 characters;
- at least one of the days is a day the school is open;
- no second note overlapping one already sent for the same child;
- a photo is a JPG or PNG under 5 MB, re-encoded before it is kept.
"""

from __future__ import annotations

import datetime as dt

from django.db.models import Q
from django.utils import timezone
from rest_framework import status

from . import audit, dates, photos
from .clock import SchoolClock
from .enums import AbsenceNoteStatus, MessageEvent, StudentStatus
from .errors import ApiError
from .models import AbsenceNote, ClassSection, Student
from .services import HolidayService

MAX_DAYS_AHEAD = 30
REASON_MIN = 10
REASON_MAX = 500
PHOTO_MAX_BYTES = 5 * 1024 * 1024
PHOTO_MAX_SIDE = 2000
PHOTO_FOLDER = "absence-notes"


class AbsenceNoteRefused(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "ABSENCE_NOTE_REFUSED"


class AbsenceNoteAlreadySent(ApiError):
    """A note for some of these days already exists; it is shown, not doubled."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "ABSENCE_NOTE_ALREADY_SENT"


def today_at(school_id: int) -> dt.date:
    return SchoolClock.for_school(school_id).now().date()


def dates_in_words(start: dt.date, end: dt.date) -> str:
    """"on 11/20/2026", "from 11/20/2026 to 11/21/2026" - the US order every
    date a person reads is written in (school/dates.py)."""
    return f"on {dates.us(start)}" if start == end else f"from {dates.us(start)} to {dates.us(end)}"


def validate(student: Student, start: dt.date, end: dt.date, reason: str) -> str:
    """The checks before anything is kept; returns the reason, trimmed."""
    today = today_at(student.school_id)
    problems: dict[str, list[str]] = {}

    if start < today:
        problems.setdefault("start_date", []).append("The first day can't be in the past.")
    if end < start:
        problems.setdefault("end_date", []).append("The last day can't be before the first.")
    if end > today + dt.timedelta(days=MAX_DAYS_AHEAD):
        problems.setdefault("end_date", []).append(f"Notes can be sent up to {MAX_DAYS_AHEAD} days ahead.")

    reason = (reason or "").strip()
    if not REASON_MIN <= len(reason) <= REASON_MAX:
        problems.setdefault("reason", []).append(
            f"Please give a reason of {REASON_MIN} to {REASON_MAX} characters."
        )

    if problems:
        raise AbsenceNoteRefused("Please check the note.", {"errors": problems})

    if not HolidayService.working_dates(student.school_id, start, end):
        raise AbsenceNoteRefused(
            "The school is closed on all of those days, so there is nothing to tell it.",
            {"errors": {"start_date": ["The school is closed on all of those days."]}},
        )

    overlapping = (
        AbsenceNote.objects.filter(student_id=student.id, start_date__lte=end, end_date__gte=start)
        .order_by("start_date")
        .first()
    )
    if overlapping is not None:
        raise AbsenceNoteAlreadySent(
            f"You already told the school about an absence {dates_in_words(overlapping.start_date, overlapping.end_date)}.",
            {"note": note_resource(overlapping)},
        )

    return reason


def send(student: Student, parent, start: dt.date, end: dt.date, reason: str, photo=None) -> AbsenceNote:
    """Keeps a parent's note and tells whoever keeps the child's register."""
    reason = validate(student, start, end, reason)

    photo_path = None
    if photo is not None:
        try:
            data, extension = photos.prepare(
                photo, max_side=PHOTO_MAX_SIDE, max_bytes=PHOTO_MAX_BYTES, noun="photo of the note"
            )
        except photos.PhotoRejected as rejected:
            raise AbsenceNoteRefused(str(rejected), {"errors": {"photo": [str(rejected)]}}) from None
        photo_path = photos.store(data, extension, folder=PHOTO_FOLDER)

    now = timezone.now()
    note = AbsenceNote.objects.create(
        school_id=student.school_id, student=student, submitted_by=parent, start_date=start, end_date=end,
        reason=reason, photo_path=photo_path, status=AbsenceNoteStatus.SENT, created_at=now, updated_at=now,
    )
    audit.record(action="absence_note.sent", module="attendance", entity_type="absence_note", entity_id=note.id,
                 school_id=student.school_id, new={"student_id": student.id, "start_date": str(start),
                                                          "end_date": str(end)})
    tell_class_teacher(note, parent)

    return note


def tell_class_teacher(note: AbsenceNote, parent) -> None:
    """An inbox message to the child's class teacher, if the class has one."""
    from .notifications import notify_staff

    section = (
        ClassSection.objects.select_related("class_teacher__school").filter(pk=note.student.class_section_id).first()
    )
    teacher = section.class_teacher if section else None
    if teacher is None:
        return

    notify_staff(
        MessageEvent.ABSENCE_NOTE, teacher,
        {"student_name": note.student.name, "guardian_name": parent.name,
         "dates": dates_in_words(note.start_date, note.end_date), "reason": note.reason},
        subject=f"Absence note: {note.student.name}",
    )


def acknowledge(note: AbsenceNote, actor) -> AbsenceNote:
    """The teacher has seen it. Acknowledging twice changes nothing."""
    if note.status == AbsenceNoteStatus.ACKNOWLEDGED:
        return note

    now = timezone.now()
    note.status = AbsenceNoteStatus.ACKNOWLEDGED
    note.acknowledged_by = actor
    note.acknowledged_at = now
    note.updated_at = now
    note.save(update_fields=["status", "acknowledged_by", "acknowledged_at", "updated_at"])
    audit.record(action="absence_note.acknowledged", module="attendance", entity_type="absence_note",
                 entity_id=note.id, school_id=note.school_id)

    return note


def for_family(student: Student):
    """The child's notes a parent sees: anything not yet over, and the last
    60 days, newest first."""
    since = today_at(student.school_id) - dt.timedelta(days=60)
    return AbsenceNote.objects.filter(student_id=student.id, end_date__gte=since).order_by("-start_date", "-id")


def covering(section_id: int, day: dt.date) -> dict[int, AbsenceNote]:
    """The notes covering one day for a class's students, by student - for
    the register."""
    return {
        note.student_id: note
        for note in AbsenceNote.objects.filter(
            student__class_section_id=section_id, start_date__lte=day, end_date__gte=day
        )
    }


def visible_to(actor, school_ids, sections_reached) -> Q:
    """Which notes a member of staff may see: their schools', and for anyone
    who keeps only some registers, those registers' children."""
    query = Q(school_id__in=school_ids, student__status=StudentStatus.ACTIVE)
    if sections_reached is not None:
        query &= Q(student__class_section_id__in=sections_reached)
    return query


def note_resource(note: AbsenceNote) -> dict:
    """A note as the Family app shows it."""
    return {
        "id": note.id,
        "start_date": note.start_date.isoformat(),
        "end_date": note.end_date.isoformat(),
        "reason": note.reason,
        "has_photo": bool(note.photo_path),
        "status": note.status,
        "acknowledged_at": note.acknowledged_at.isoformat() if note.acknowledged_at else None,
        "sent_at": note.created_at.isoformat() if note.created_at else None,
    }


def staff_note_resource(note: AbsenceNote) -> dict:
    """A note as the school sees it."""
    student = note.student
    return {
        **note_resource(note),
        "student": {"id": student.id, "name": student.name, "class_section_id": student.class_section_id},
        "sent_by": note.submitted_by.name,
        "acknowledged_by": note.acknowledged_by.name if note.acknowledged_by_id else None,
    }
