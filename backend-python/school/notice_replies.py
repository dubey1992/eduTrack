"""Notices that ask parents for an answer - a consent slip, an RSVP
(docs/parent-student-app.md, F5, decided 2026-11-17).

The school writes a question on an announcement that reaches parents ("Can
your child come on the trip to the science museum?") and, if it likes, the
last day it takes answers. In the Family app a parent answers Yes or No for
each of their children the notice is about, with a note if they want, and
may change their mind until that day. The school sees how many said yes and
no, and who has not answered yet.

One answer per child, not per parent: the count a trip needs is of children.
"""

from __future__ import annotations

from django.utils import timezone
from rest_framework import status

from . import audit
from .clock import SchoolClock
from .enums import AnnouncementAudience
from .errors import ApiError
from .models import Announcement, AnnouncementReply, Student

QUESTION_MAX = 200
NOTE_MAX = 300


class ReplyRefused(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "REPLY_REFUSED"


class RepliesClosed(ApiError):
    status_code = status.HTTP_409_CONFLICT
    error_code = "REPLIES_CLOSED"


def asks(announcement: Announcement) -> bool:
    return bool(announcement.reply_question) and AnnouncementAudience.reaches_guardians(announcement.audience_type)


def audience_students(announcement: Announcement):
    from .services import AnnouncementService

    return AnnouncementService.students(announcement.school_id, announcement.audience_type, announcement.audience_id)


def is_open(announcement: Announcement) -> bool:
    if announcement.reply_by is None:
        return True
    return SchoolClock.for_school(announcement.school_id).now().date() <= announcement.reply_by


def children_asked(announcement: Announcement, children) -> list[Student]:
    """The caller's own children this notice asks about."""
    if not asks(announcement):
        return []
    ids = set(audience_students(announcement).values_list("id", flat=True))
    return [child for child in children if child.id in ids]


def reply_block(announcement: Announcement, children) -> dict | None:
    """What the Family app shows under a notice that asks: the question, the
    closing day, and each of the parent's children with their answer so far."""
    asked = children_asked(announcement, children)
    if not asked:
        return None

    answers = {
        reply.student_id: reply
        for reply in AnnouncementReply.objects.filter(announcement_id=announcement.id, student_id__in=[c.id for c in asked])
    }

    return {
        "question": announcement.reply_question,
        "reply_by": announcement.reply_by.isoformat() if announcement.reply_by else None,
        "open": is_open(announcement),
        "children": [
            {
                "student_id": child.id,
                "name": child.first_name,
                "answer": answers[child.id].answer if child.id in answers else None,
                "note": answers[child.id].note if child.id in answers else None,
            }
            for child in asked
        ],
    }


def answer(announcement: Announcement, child: Student, parent, value: bool, note: str | None) -> AnnouncementReply:
    """A parent's answer for one child; a later one replaces it until closing."""
    if not is_open(announcement):
        raise RepliesClosed("Answers for this notice have closed. Please contact the school office.")

    note = (note or "").strip() or None
    if note is not None and len(note) > NOTE_MAX:
        raise ReplyRefused("Please check the note.", {"errors": {"note": [f"Please keep the note to {NOTE_MAX} characters."]}})

    now = timezone.now()
    reply, created = AnnouncementReply.objects.update_or_create(
        announcement_id=announcement.id, student_id=child.id,
        defaults={"school_id": announcement.school_id, "answered_by": parent, "answer": value, "note": note,
                  "updated_at": now},
        create_defaults={"school_id": announcement.school_id, "answered_by": parent, "answer": value, "note": note,
                         "created_at": now, "updated_at": now},
    )
    audit.record(action="announcement.replied" if created else "announcement.reply_changed", module="announcements",
                 entity_type="announcement", entity_id=announcement.id, school_id=announcement.school_id,
                 new={"student_id": child.id, "answer": value})
    return reply


def summary(announcement: Announcement) -> dict:
    """For the school: how many said yes and no, and who has not answered."""
    students = list(audience_students(announcement).select_related("class_section__school_class").order_by(
        "class_section__school_class__level", "class_section__name", "first_name", "id"))
    replies = {
        reply.student_id: reply
        for reply in AnnouncementReply.objects.select_related("answered_by").filter(announcement_id=announcement.id)
    }

    def row(student: Student) -> dict:
        reply = replies.get(student.id)
        section = student.class_section
        return {
            "student_id": student.id,
            "name": student.name,
            "class_name": f"{section.school_class.name} {section.name}" if section else None,
            "answer": reply.answer if reply else None,
            "note": reply.note if reply else None,
            "answered_by": reply.answered_by.name if reply else None,
        }

    rows = [row(student) for student in students]
    return {
        "question": announcement.reply_question,
        "reply_by": announcement.reply_by.isoformat() if announcement.reply_by else None,
        "open": is_open(announcement),
        "yes": sum(1 for r in rows if r["answer"] is True),
        "no": sum(1 for r in rows if r["answer"] is False),
        "waiting": sum(1 for r in rows if r["answer"] is None),
        "students": rows,
    }
