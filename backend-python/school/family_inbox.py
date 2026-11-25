"""The Family app's notices: the school's messages to a guardian, in the
guardian's own inbox (docs/parent-student-app.md, F1).

Until F1 a guardian had no login, so every message to one was an SMS, a
WhatsApp or an email and nothing else (notifications.outcome_for). A guardian
with a Family account now also gets an in-app copy of the same words, on the
ordinary inbox row the staff apps use - so read and unread, the feed and the
push that rides on an in-app message all work as they do for staff.

What this does not change: the school's SMS and WhatsApp go out exactly as
before. The copy is extra, never instead.

Each copy follows, in order:
- the school's switches (the communication module, that kind of alert) -
  the caller has already applied those before calling;
- the Family App module being on for the school;
- the parent's own switch for that kind of message (FamilyNotificationSetting),
  except an emergency, which always arrives;
- one copy per announcement per parent: a parent of two children at a school
  gets a whole-school notice once, not twice.
"""

from __future__ import annotations

import logging

from django.utils import timezone

from . import modules
from .enums import MessageCategory, MessageChannel, MessageEvent, MessageStatus, StudentStatus, UserRole, UserStatus
from .models import FamilyNotificationSetting, GuardianStudent, Message

logger = logging.getLogger(__name__)

MODULE = "family_app"

# Each kind of message, and the parent's switch that decides it. An
# emergency has none, on purpose.
SWITCHES = {
    MessageCategory.ATTENDANCE: "attendance",
    MessageCategory.TRANSPORT: "transport",
    MessageCategory.FEE: "fee",
    MessageCategory.RESULT: "result",
    MessageCategory.ANNOUNCEMENT: "notices",
    MessageCategory.GENERAL: "notices",
}
ALWAYS = (MessageCategory.EMERGENCY,)
# Events with a switch of their own, whatever their category: homework is
# about teaching, which otherwise never reaches a guardian (M8, 8.1).
EVENT_SWITCHES = {
    MessageEvent.HOMEWORK_FOR_FAMILY: "homework",
    # Parent-teacher meetings (M12, 8.4): a message from the school, so Notices.
    MessageEvent.PTM_SLOTS_OPEN: "notices",
    MessageEvent.PTM_REMINDER: "notices",
    MessageEvent.PTM_BOOKING_CANCELLED: "notices",
}
SETTINGS = ("attendance", "transport", "fee", "result", "notices", "homework")


def settings_of(user) -> dict:
    """The parent's switches, every one on when they never changed any."""
    row = FamilyNotificationSetting.objects.filter(user_id=user.id).first()

    return {name: getattr(row, name) if row else True for name in SETTINGS}


def save_settings(user, changes: dict) -> dict:
    now = timezone.now()
    row, _ = FamilyNotificationSetting.objects.get_or_create(
        user_id=user.id, defaults={"created_at": now, "updated_at": now}
    )

    for name in SETTINGS:
        if name in changes:
            setattr(row, name, bool(changes[name]))

    row.updated_at = now
    row.save()

    return settings_of(user)


def wants(user_id, category: str, settings_by_user: dict, event: str | None = None) -> bool:
    if category in ALWAYS:
        return True

    switch = EVENT_SWITCHES.get(event) or SWITCHES.get(category)
    if switch is None:
        # Teaching, leave - never addressed to a guardian.
        return False

    return settings_by_user.get(user_id, {}).get(switch, True)


def family_accounts_of(student):
    """The active family accounts of this student's guardians."""
    return [
        link.guardian
        for link in GuardianStudent.objects.select_related("guardian__user").filter(
            student_id=student.id,
            guardian__user__isnull=False,
            guardian__user__role=UserRole.PARENT,
            guardian__user__status=UserStatus.ACTIVE,
        )
    ]


def copy_to_family(event: str, student, render_for, subject=None, announcement=None, actor=None) -> list[Message]:
    """Writes an in-app copy for each of the student's guardians who has the
    Family app. `render_for(guardian)` gives the words, addressed to that
    guardian rather than to the student's primary one.

    Returns the rows written; the caller queues them like any other.
    """
    if student.school_id is None or student.status != StudentStatus.ACTIVE:
        return []

    if not modules.is_enabled(student.school_id, MODULE):
        return []

    # A progress report is its attachment, which an inbox cannot carry.
    if event == MessageEvent.PROGRESS_REPORT:
        return []

    category = MessageEvent.category(event)
    guardians = family_accounts_of(student)
    if not guardians:
        return []

    settings_by_user = {
        row.user_id: {name: getattr(row, name) for name in SETTINGS}
        for row in FamilyNotificationSetting.objects.filter(user_id__in=[g.user_id for g in guardians])
    }

    written = []
    now = timezone.now()

    for guardian in guardians:
        if not wants(guardian.user_id, category, settings_by_user, event):
            continue

        if announcement is not None and Message.objects.filter(
            announcement_id=announcement.id, user_id=guardian.user_id, channel=MessageChannel.IN_APP
        ).exists():
            continue

        # Like notifications.record, a problem here must never roll back the
        # caller's own work - a register, a trip.
        try:
            written.append(
                Message.objects.create(
                    school_id=student.school_id,
                    event=event,
                    announcement_id=announcement.id if announcement else None,
                    category=category,
                    channel=MessageChannel.IN_APP,
                    recipient_name=guardian.name,
                    user_id=guardian.user_id,
                    student_id=student.id,
                    student_name=student.name,
                    subject=announcement.title if announcement else subject,
                    body=render_for(guardian),
                    status=MessageStatus.QUEUED,
                    created_by_id=actor.id if actor else None,
                    created_at=now,
                    updated_at=now,
                )
            )
        except Exception:
            logger.exception("Could not write a Family app copy (event %s, student %s)", event, student.id)

    return written
