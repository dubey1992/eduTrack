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

**Channels.** A message reaches a person on every channel the school has
switched on that the person has an address for: SMS and WhatsApp need a
mobile number, email an address, and the in-app inbox a login - which
guardians do not have. A channel the school has not switched on is not
recorded at all; a channel it wanted but has no address for is recorded as
skipped, so the missing number can be noticed and fixed.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from django.utils import timezone

from . import crypto, queue
from .clock import SchoolClock
from .enums import (
    AttendanceAlertMode,
    MessageCategory,
    MessageChannel,
    MessageEvent,
    MessageStatus,
)
from .models import CommunicationSetting, Message, MessageTemplate, School, WhatsappTemplate

logger = logging.getLogger(__name__)

SEND_MESSAGE = "send_message"

# What a school gets before it has ever opened the settings screen. Absent-only
# alerts by default: a text every morning saying a child turned up is a text
# every parent learns to ignore. WhatsApp and email are off until the school
# sets a provider up and turns them on.
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
    "whatsapp_enabled": False,
    "whatsapp_provider": "log",
    "email_enabled": False,
    "credentials": None,
}

TOKEN = re.compile(r"\{([a-z_]+)\}")

NO_MOBILE = "No mobile number on record."
NO_EMAIL = "No email address on record."
NO_WHATSAPP_TEMPLATE = "No WhatsApp template is mapped for this message."


@dataclass(frozen=True)
class Recipient:
    """Who a message is for, and how they can be reached. `user` is set for
    somebody with a login, `student` for a message about (or to) a student."""

    name: str
    mobile: str | None = None
    email: str | None = None
    user: object = None
    student: object = None

    def address_for(self, channel: str) -> str | None:
        if channel in (MessageChannel.SMS, MessageChannel.WHATSAPP):
            return self.mobile

        if channel == MessageChannel.EMAIL:
            return self.email

        return None


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


def credentials_of(setting: CommunicationSetting, provider: str) -> dict:
    """The school's account with one provider, decrypted - {} when none."""
    return crypto.decrypt_json(setting.credentials).get(provider) or {}


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

    A message somebody wrote by hand is never switched off: the switches are
    for the alerts modules raise on their own.
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


def channel_enabled(channel: str, setting: CommunicationSetting) -> bool:
    """Whether the school sends on this channel at all. The inbox is always
    on: it costs nothing and no provider is involved."""
    return {
        MessageChannel.IN_APP: True,
        MessageChannel.SMS: setting.sms_enabled,
        MessageChannel.WHATSAPP: setting.whatsapp_enabled,
        MessageChannel.EMAIL: setting.email_enabled,
    }[channel]


def enabled_channels(setting: CommunicationSetting) -> list[str]:
    return [channel for channel in MessageChannel.values if channel_enabled(channel, setting)]


def outcome_for(channel: str, setting: CommunicationSetting, recipient: Recipient) -> tuple[str | None, str | None]:
    """What becomes of this channel's copy.

    A None status means the message is not recorded at all.
    """
    if channel == MessageChannel.IN_APP:
        # The inbox belongs to a login. A guardian has none, so there is
        # nothing to skip - the copy simply does not exist.
        return (MessageStatus.QUEUED, None) if recipient.user is not None else (None, None)

    if not channel_enabled(channel, setting):
        return None, None

    # The school wanted to reach this person here but has no address for
    # them. That is a record to fix, so it belongs in the log.
    if not recipient.address_for(channel):
        return MessageStatus.SKIPPED, NO_EMAIL if channel == MessageChannel.EMAIL else NO_MOBILE

    return MessageStatus.QUEUED, None


def whatsapp_payload(school_id: int, event: str, tokens: dict) -> dict | None:
    """The template a WhatsApp copy is sent as, filled in now - or None when
    the school has not mapped one for this event."""
    mapping = WhatsappTemplate.objects.filter(school_id=school_id, event=event).first()

    if mapping is None:
        return None

    return {
        "template": mapping.template_name,
        "language": mapping.language,
        "values": [str(tokens.get(name) or "") for name in mapping.parameter_names()],
    }


def provider_for(channel: str, setting: CommunicationSetting) -> str | None:
    return {
        MessageChannel.SMS: setting.provider,
        MessageChannel.WHATSAPP: setting.whatsapp_provider,
        MessageChannel.EMAIL: "smtp",
        MessageChannel.IN_APP: None,
    }[channel]


def school_name(school_id) -> str | None:
    return School.objects.filter(pk=school_id).values_list("name", flat=True).first()


def stamp(clock: SchoolClock) -> dict:
    return {"date": clock.now().strftime("%m/%d/%Y"), "time": clock.now().strftime("%I:%M %p").lstrip("0")}


def notify_guardian(event: str, student, tokens: dict, actor=None, channels=None, announcement=None, subject=None):
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
        "recipient_name": student.guardian_name,
        "school_name": school_name(student.school_id),
        **stamp(clock),
        **tokens,
    }

    return record(
        event,
        school_id=student.school_id,
        recipient=Recipient(
            name=student.guardian_name, mobile=student.guardian_mobile, email=student.guardian_email, student=student
        ),
        tokens=tokens,
        actor=actor,
        channels=channels,
        announcement=announcement,
        subject=subject,
    )


def notify_student(event: str, student, tokens: dict, actor=None, channels=None, announcement=None, subject=None):
    """Tells a student something directly, on their own number or address -
    an older student the school has contact details for."""
    clock = SchoolClock.for_school(student.school_id)

    tokens = {
        "student_name": student.name,
        "guardian_name": student.guardian_name,
        "recipient_name": student.name,
        "school_name": school_name(student.school_id),
        **stamp(clock),
        **tokens,
    }

    return record(
        event,
        school_id=student.school_id,
        recipient=Recipient(
            name=student.name, mobile=student.student_mobile, email=student.student_email, student=student
        ),
        tokens=tokens,
        actor=actor,
        channels=channels,
        announcement=announcement,
        subject=subject,
    )


def notify_staff(event: str, user, tokens: dict, actor=None, channels=None, announcement=None, subject=None):
    """Tells a member of staff something, in their inbox and on every channel
    the school has on."""
    clock = SchoolClock.for_user(user)

    tokens = {
        "staff_name": user.name,
        "recipient_name": user.name,
        "school_name": user.school.name if user.school_id else None,
        **stamp(clock),
        **tokens,
    }

    return record(
        event,
        school_id=user.school_id,
        recipient=Recipient(name=user.name, mobile=user.mobile, email=user.email, user=user),
        tokens=tokens,
        actor=actor,
        channels=channels,
        announcement=announcement,
        subject=subject,
    )


def record(
    event: str,
    school_id,
    recipient: Recipient,
    tokens: dict,
    actor=None,
    channels=None,
    announcement=None,
    subject=None,
) -> list[Message]:
    """Writes what should be sent, and queues the sending."""
    if school_id is None:
        return []

    setting = settings_for(school_id)

    if switched_off(event, setting):
        return []

    body = render(body_for(school_id, event), tokens)
    subject = announcement.title if announcement else subject
    messages = []
    now = timezone.now()
    whatsapp = None

    for channel in channels or MessageEvent.channels(event):
        status, reason = outcome_for(channel, setting, recipient)

        if status is None:
            continue

        if channel == MessageChannel.WHATSAPP and status == MessageStatus.QUEUED:
            whatsapp = whatsapp_payload(school_id, event, tokens)

            if whatsapp is None:
                status, reason = MessageStatus.SKIPPED, NO_WHATSAPP_TEMPLATE

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
                    recipient_name=recipient.name,
                    recipient_mobile=recipient.mobile if channel in (MessageChannel.SMS, MessageChannel.WHATSAPP) else None,
                    recipient_email=recipient.email if channel == MessageChannel.EMAIL else None,
                    user_id=recipient.user.id if recipient.user else None,
                    student_id=recipient.student.id if recipient.student else None,
                    student_name=recipient.student.name if recipient.student else None,
                    subject=subject,
                    body=body,
                    template_parameters=whatsapp if channel == MessageChannel.WHATSAPP else None,
                    status=status,
                    provider=provider_for(channel, setting),
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
