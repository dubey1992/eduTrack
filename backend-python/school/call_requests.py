"""A parent's "please call me" (docs/parent-student-app.md, F5, decided
2026-11-17).

From the Family app a parent asks the child's class teacher or the school
office to ring them, says what it is about and, if they like, when suits
them. It arrives in that person's inbox (or, for the office, every School
Admin's), never as an SMS. Whoever it is for calls the number shown and
marks it called with a note of how it went; the parent sees "Called".

No open chat (decision D5): this is a request for a call, nothing more.

The rules a parent meets:
- the class teacher only when the class has one - otherwise the office;
- a reason of 5 to 300 characters, a "good time" of up to 100;
- one open request per child to each of the two - a second is answered
  with the first, not added beside it.
"""

from __future__ import annotations

from django.utils import timezone
from rest_framework import status

from . import audit
from .enums import MessageEvent, UserRole
from .errors import ApiError
from .models import CallRequest, ClassSection, Guardian, Student, User

CLASS_TEACHER = "class_teacher"
OFFICE = "office"
RECIPIENTS = (CLASS_TEACHER, OFFICE)

OPEN = "open"
CALLED = "called"

REASON_MIN = 5
REASON_MAX = 300
TIME_MAX = 100
NOTE_MAX = 500


class CallRequestRefused(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "CALL_REQUEST_REFUSED"


class CallRequestAlreadyOpen(ApiError):
    status_code = status.HTTP_409_CONFLICT
    error_code = "CALL_REQUEST_OPEN"


def class_teacher_of(student: Student) -> User | None:
    section = ClassSection.objects.select_related("class_teacher").filter(pk=student.class_section_id).first()
    return section.class_teacher if section else None


def ask(student: Student, parent: User, recipient: str, reason: str, preferred_time: str | None) -> CallRequest:
    reason = (reason or "").strip()
    preferred_time = (preferred_time or "").strip() or None
    problems: dict[str, list[str]] = {}

    if recipient not in RECIPIENTS:
        problems["recipient"] = ["Choose who should call: the class teacher or the school office."]
    if not REASON_MIN <= len(reason) <= REASON_MAX:
        problems["reason"] = [f"Please say what it is about, in {REASON_MIN} to {REASON_MAX} characters."]
    if preferred_time is not None and len(preferred_time) > TIME_MAX:
        problems["preferred_time"] = [f"Please keep it to {TIME_MAX} characters."]
    if problems:
        raise CallRequestRefused("Please check the request.", {"errors": problems})

    teacher = None
    if recipient == CLASS_TEACHER:
        teacher = class_teacher_of(student)
        if teacher is None:
            raise CallRequestRefused(
                f"{student.first_name}'s class has no class teacher set yet. Please ask the school office.",
                {"errors": {"recipient": ["This class has no class teacher yet - choose the school office."]}},
            )

    open_one = CallRequest.objects.filter(student_id=student.id, recipient=recipient, status=OPEN).first()
    if open_one is not None:
        who = "the class teacher" if recipient == CLASS_TEACHER else "the school office"
        raise CallRequestAlreadyOpen(
            f"You've already asked {who} to call - they will ring you.", {"request": request_resource(open_one)}
        )

    now = timezone.now()
    request = CallRequest.objects.create(
        school_id=student.school_id, student=student, requested_by=parent, recipient=recipient,
        teacher_user=teacher, reason=reason, preferred_time=preferred_time, status=OPEN,
        created_at=now, updated_at=now,
    )
    audit.record(action="call_request.sent", module="communication", entity_type="call_request",
                 entity_id=request.id, school_id=student.school_id)
    tell_recipients(request, parent)

    return request


def recipients_of(request: CallRequest):
    """Who hears of it: the class teacher, or every School Admin of the school."""
    if request.recipient == CLASS_TEACHER and request.teacher_user_id:
        return [request.teacher_user]
    return list(User.objects.filter(school_id=request.school_id, role=UserRole.SCHOOL_ADMIN, status="active"))


def tell_recipients(request: CallRequest, parent: User) -> None:
    from .notifications import notify_staff

    tokens = {
        "student_name": request.student.name,
        "guardian_name": parent.name,
        "mobile": parent_mobile(parent) or "",
        "reason": request.reason,
        "preferred_time": request.preferred_time or "any time",
    }
    for person in recipients_of(request):
        notify_staff(MessageEvent.CALL_REQUEST, person, tokens, subject=f"Please call: {parent.name}")


def parent_mobile(parent: User) -> str | None:
    guardian = Guardian.objects.filter(user_id=parent.id).first()
    return (guardian.login_mobile if guardian else None) or parent.mobile


def may_handle(actor: User, request: CallRequest) -> bool:
    """The class teacher it was sent to; any of the school's admins for either."""
    if actor.role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.SUPER_ADMIN):
        from .scope import SchoolScope

        return SchoolScope.for_actor(actor).apply_to(CallRequest.objects.filter(pk=request.pk)).exists()
    return request.teacher_user_id == actor.id


def mark_called(request: CallRequest, actor: User, note: str | None) -> CallRequest:
    note = (note or "").strip() or None
    if note is not None and len(note) > NOTE_MAX:
        raise CallRequestRefused("Please check the note.", {"errors": {"outcome_note": [
            f"Please keep the note to {NOTE_MAX} characters."]}})

    if request.status == CALLED:
        return request

    now = timezone.now()
    request.status = CALLED
    request.called_by = actor
    request.called_at = now
    request.outcome_note = note
    request.updated_at = now
    request.save(update_fields=["status", "called_by", "called_at", "outcome_note", "updated_at"])
    audit.record(action="call_request.called", module="communication", entity_type="call_request",
                 entity_id=request.id, school_id=request.school_id)

    return request


def request_resource(request: CallRequest) -> dict:
    """A request as the Family app shows it: the outcome note is the school's
    and stays with the school."""
    return {
        "id": request.id,
        "recipient": request.recipient,
        "reason": request.reason,
        "preferred_time": request.preferred_time,
        "status": request.status,
        "sent_at": request.created_at.isoformat() if request.created_at else None,
        "called_at": request.called_at.isoformat() if request.called_at else None,
    }


def staff_request_resource(request: CallRequest) -> dict:
    return {
        **request_resource(request),
        "student": {"id": request.student_id, "name": request.student.name},
        "parent": {"name": request.requested_by.name, "mobile": parent_mobile(request.requested_by)},
        "teacher_name": request.teacher_user.name if request.teacher_user_id else None,
        "called_by": request.called_by.name if request.called_by_id else None,
        "outcome_note": request.outcome_note,
    }
