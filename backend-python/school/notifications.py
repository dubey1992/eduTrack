"""Telling somebody something happened.

Port of NotificationService, TemplateRenderer, CommunicationSettingService and
MessageTemplateService - the core of the Communication module without its
endpoints.

**It arrives before the modules the plan put it after, and deliberately.**
M10 is attendance, leave and the timetable; M11 is communication. But marking
a register alerts a guardian, approving leave alerts the person who asked for
it, and a bus trip alerts both. Porting attendance without this would give a
school a backend that looks finished and silently stops sending absence
alerts - the same failure that kept payments waiting for its queue. So the
core comes first and the endpoints come with M11.

Nothing here talks to a gateway. It records what should be sent and queues the
sending, because a school marking a register must never wait on an SMS
provider, and a provider being down must never roll back a register.
"""

from __future__ import annotations

import logging
import re

from django.utils import timezone

from . import queue
from .clock import SchoolClock
from .enums import (
    AttendanceAlertMode,
    MessageCategory,
    MessageChannel,
    MessageEvent,
    MessageStatus,
)
from .models import CommunicationSetting, Message, MessageTemplate, School

logger = logging.getLogger(__name__)

SEND_MESSAGE = "send_message"

# What a school gets before it has ever opened the settings screen. Absent-only
# alerts by default: a text every morning saying a child turned up is a text
# every parent learns to ignore.
DEFAULTS = {
    "sms_enabled": True,
    "attendance_alerts": AttendanceAlertMode.ABSENT_ONLY,
    "transport_alerts_enabled": True,
    "leave_alerts_enabled": True,
    "sender_id": None,
    # "log" is the prototype's Demo Gateway: it records the message and writes
    # it to the log without calling anybody. Nothing reaches a phone, and the
    # product says so rather than letting a school read "Sent" and assume a
    # parent was told.
    "provider": "log",
}

TOKEN = re.compile(r"\{([a-z_]+)\}")


def render(body: str, tokens: dict) -> str:
    """Fills {token} placeholders.

    A token the caller did not supply is blanked rather than left as literal
    braces, so a reworded template can never leak "{student_name}" into a
    parent's SMS.
    """
    filled = TOKEN.sub(lambda match: str(tokens.get(match.group(1)) or ""), body)

    return re.sub(r"[ \t]{2,}", " ", filled).strip()


def unknown_tokens(body: str, allowed) -> list[str]:
    """Tokens a body uses that its event does not provide."""
    used = dict.fromkeys(TOKEN.findall(body))

    return [token for token in used if token not in allowed]


def settings_for(school_id: int) -> CommunicationSetting:
    """A school's alert switches.

    Reading never writes a row: a school that has never opened the settings
    screen gets the defaults, and gets them without the act of asking creating
    a record.
    """
    existing = CommunicationSetting.objects.filter(school_id=school_id).first()

    if existing is not None:
        return existing

    return CommunicationSetting(school_id=school_id, **DEFAULTS)


def body_for(school_id: int, event: str) -> str:
    """The wording this school will actually send.

    A school only gets a row when it overrides an event, so the defaults on
    the event stay the single source of truth for everybody else - and a
    school that overrode an alert and then switched the override off falls
    back rather than sending nothing.
    """
    override = MessageTemplate.objects.filter(school_id=school_id, event=event).first()

    if override is not None and override.is_active:
        return override.body

    return MessageEvent.default_body(event)


def switched_off(event: str, setting: CommunicationSetting) -> bool:
    """Has the school turned this kind of alert off?

    A switched-off alert is not "skipped" and is not logged. The school never
    wanted the message, and one row per student per day would bury the log.
    Only a message the school *did* want but that could not be delivered is
    worth recording as skipped.
    """
    category = MessageEvent.category(event)

    if category == MessageCategory.ATTENDANCE:
        if setting.attendance_alerts == AttendanceAlertMode.OFF:
            return True

        if setting.attendance_alerts == AttendanceAlertMode.ABSENT_ONLY:
            return event == MessageEvent.ATTENDANCE_PRESENT

        return False

    if category == MessageCategory.TRANSPORT:
        return not setting.transport_alerts_enabled

    if category == MessageCategory.LEAVE:
        return not setting.leave_alerts_enabled

    return False


def outcome_for(channel: str, sms_enabled: bool, mobile) -> tuple[str | None, str | None]:
    """What becomes of this channel's copy.

    A None status means the message is not recorded at all.
    """
    if channel == MessageChannel.IN_APP:
        return MessageStatus.QUEUED, None

    if not sms_enabled:
        return None, None

    # The school wanted to text this person but has no number for them. That
    # is a record to fix, so it belongs in the log.
    if not mobile:
        return MessageStatus.SKIPPED, "No mobile number on record."

    return MessageStatus.QUEUED, None


def notify_guardian(event: str, student, tokens: dict, actor=None, channels=None, announcement=None):
    """Tells a student's guardian something."""
    # The guardian reads this on a phone in the school's country, so the date
    # and time inside the text are the school's, not the server's.
    #
    # Reached through school_id rather than `student.school`: Laravel's `?->`
    # yields null on a missing relation and Django *raises*, so the PHP
    # version of this line is safe on a student with no school and a direct
    # port of it is not.
    clock = SchoolClock.for_school(student.school_id)

    tokens = {
        "student_name": student.name,
        "guardian_name": student.guardian_name,
        "school_name": School.objects.filter(pk=student.school_id).values_list("name", flat=True).first(),
        "date": clock.now().strftime("%m/%d/%Y"),
        "time": clock.now().strftime("%I:%M %p").lstrip("0"),
        **tokens,
    }

    return record(
        event,
        school_id=student.school_id,
        recipient_name=student.guardian_name,
        mobile=student.guardian_mobile,
        tokens=tokens,
        actor=actor,
        student=student,
        channels=channels,
        announcement=announcement,
    )


def notify_staff(event: str, user, tokens: dict, actor=None, channels=None, announcement=None):
    """Tells a member of staff something, in their inbox and by SMS."""
    clock = SchoolClock.for_user(user)

    tokens = {
        "staff_name": user.name,
        "school_name": user.school.name if user.school_id else None,
        "date": clock.now().strftime("%m/%d/%Y"),
        "time": clock.now().strftime("%I:%M %p").lstrip("0"),
        **tokens,
    }

    return record(
        event,
        school_id=user.school_id,
        recipient_name=user.name,
        mobile=user.mobile,
        tokens=tokens,
        actor=actor,
        user=user,
        channels=channels,
        announcement=announcement,
    )


def record(
    event: str,
    school_id,
    recipient_name: str,
    mobile,
    tokens: dict,
    actor=None,
    student=None,
    user=None,
    channels=None,
    announcement=None,
) -> list[Message]:
    """Writes what should be sent, and queues the sending."""
    if school_id is None:
        return []

    setting = settings_for(school_id)

    if switched_off(event, setting):
        return []

    body = render(body_for(school_id, event), tokens)
    messages = []
    now = timezone.now()

    for channel in channels or MessageEvent.channels(event):
        status, reason = outcome_for(channel, setting.sms_enabled, mobile)

        if status is None:
            continue

        # Callers write this from inside their own transaction - marking a
        # register, ending a trip. A messaging problem must never roll their
        # work back, so it is logged and swallowed here.
        try:
            messages.append(
                Message.objects.create(
                    school_id=school_id,
                    event=event,
                    announcement_id=announcement.id if announcement else None,
                    category=MessageEvent.category(event),
                    channel=channel,
                    recipient_name=recipient_name,
                    recipient_mobile=mobile if channel == MessageChannel.SMS else None,
                    user_id=user.id if user else None,
                    student_id=student.id if student else None,
                    student_name=student.name if student else None,
                    subject=announcement.title if announcement else None,
                    body=body,
                    status=status,
                    provider=setting.provider if channel == MessageChannel.SMS else None,
                    failure_reason=reason,
                    created_by_id=actor.id if actor else None,
                    sent_at=now if status == MessageStatus.SENT else None,
                    created_at=now,
                    updated_at=now,
                )
            )
        except Exception:
            logger.exception(
                "Could not record an outgoing message (event %s, channel %s, school %s)",
                event,
                channel,
                school_id,
            )

    for message in messages:
        if message.status == MessageStatus.QUEUED:
            queue.push(SEND_MESSAGE, {"message_id": message.id})

    return messages
