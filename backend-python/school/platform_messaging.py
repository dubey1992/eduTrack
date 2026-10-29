"""School365ai's own SMS and WhatsApp account (docs/platform-messaging.md,
M1, decided 2026-10-29).

Every school's messages go through one Twilio account and a shared sender
that School365ai owns and charges schools for. So the provider, its keys and
the WhatsApp templates live here, set by the Super Admin, rather than on
each school's settings. A school keeps only what it decides: which channels
are on and which alerts go out.

With nothing saved, or the provider left on the Demo Gateway ("log"),
messages are recorded and nobody's phone rings - and the screens say so.
"""

from __future__ import annotations

from django.utils import timezone

from . import audit, crypto, sms, whatsapp
from .enums import MessageChannel, MessageEvent
from .gateways import Result, Template
from .models import PlatformMessaging, PlatformWhatsappTemplate, User
from .gateways.twilio import CREDENTIALS as TWILIO_FIELDS

# The providers the platform may send through: the Demo Gateway, which sends
# nothing, and Twilio (decided 2026-10-29).
PROVIDERS = ("log", "twilio")

# What each provider asks for: (key, label, secret).
FIELDS = {"log": (), "twilio": TWILIO_FIELDS}


def current() -> PlatformMessaging:
    """The saved account, or an unsaved Demo Gateway one. Reading never
    writes a row."""
    return PlatformMessaging.objects.order_by("id").first() or PlatformMessaging(provider="log")


def provider() -> str:
    name = current().provider

    return name if name in PROVIDERS else "log"


def credentials() -> dict:
    """The account's keys, decrypted - {} for the Demo Gateway."""
    return crypto.decrypt_json(current().credentials) or {}


def provider_for(channel: str) -> str | None:
    """Which gateway carries a channel now. Email has its own (SMTP), the
    inbox none."""
    if channel in (MessageChannel.SMS, MessageChannel.WHATSAPP):
        return provider()

    return {MessageChannel.EMAIL: "smtp"}.get(channel)


def sms_delivers() -> bool:
    return sms.delivers(provider())


def whatsapp_delivers() -> bool:
    return whatsapp.delivers(provider())


def send_sms(to: str, body: str) -> Result:
    return sms.gateway(provider()).send(to, body, None, credentials())


def send_whatsapp(to: str, template: Template) -> Result:
    return whatsapp.gateway(provider()).send_template(to, template, credentials())


# -- the account --------------------------------------------------------------


def save(data: dict, actor: User) -> PlatformMessaging:
    """Saves the provider and its keys. A key that is sent replaces the
    stored one, an empty one clears it, and one left out is kept - so the
    screen never has to send a secret back to keep it."""
    row = current()
    before = audit.fields_of(row) if row.pk else {}
    now = timezone.now()

    stored = crypto.decrypt_json(row.credentials) or {}
    for key, value in (data.get("credentials") or {}).items():
        if value in (None, ""):
            stored.pop(key, None)
        else:
            stored[key] = value.strip()

    row.provider = data.get("provider", row.provider)
    row.credentials = crypto.encrypt_json(stored) if stored else None
    row.updated_by_id = actor.id
    row.updated_at = now

    if row.pk is None:
        row.created_at = now
        row.save()
        audit.created("communication", row)
    else:
        row.save()
        audit.updated("communication", row, before)

    return row


def test(channel: str, to: str, actor: User) -> Result:
    """One message through the platform's account, now, so the Super Admin
    learns whether it works before a parent does. The outcome is kept on the
    account so the screen can say when it last worked."""
    if channel == MessageChannel.SMS:
        result = send_sms(to, "This is a test message from School365ai. Your messaging account works.")
    else:
        mapping = PlatformWhatsappTemplate.objects.filter(event=MessageEvent.GENERAL_MESSAGE).first()
        if mapping is None:
            result = Result(
                accepted=False,
                failure_reason='Map a WhatsApp template to the "Message" event first, then test again.',
            )
        else:
            values = {"recipient_name": "Test", "subject": "Test message", "school_name": "School365ai",
                      "body": "This is a test message. Your messaging account works."}
            result = send_whatsapp(
                to,
                Template(
                    name=mapping.template_name,
                    language=mapping.language,
                    values=[values.get(name, "") for name in mapping.parameter_names()],
                ),
            )

    row = current()
    if row.pk is not None:
        row.last_tested_at = timezone.now()
        row.last_test_error = None if result.accepted else (result.failure_reason or "")[:255]
        row.save(update_fields=["last_tested_at", "last_test_error"])

    return result


# -- WhatsApp templates -------------------------------------------------------


def templates_by_event() -> dict:
    return {row.event: row for row in PlatformWhatsappTemplate.objects.all()}


def whatsapp_payload(event: str, tokens: dict) -> dict | None:
    """The template a WhatsApp copy goes as, filled in now - or None when no
    template is mapped for the event."""
    mapping = PlatformWhatsappTemplate.objects.filter(event=event).first()

    if mapping is None:
        return None

    return {
        "template": mapping.template_name,
        "language": mapping.language,
        "values": [str(tokens.get(name) or "") for name in mapping.parameter_names()],
    }


def set_template(event: str, data: dict, actor: User) -> PlatformWhatsappTemplate:
    now = timezone.now()
    values = {
        "template_name": data["template_name"],
        "language": data.get("language") or "en",
        "parameters": ",".join(data.get("parameters") or []) or None,
    }
    existing = PlatformWhatsappTemplate.objects.filter(event=event).first()

    if existing is None:
        row = PlatformWhatsappTemplate.objects.create(
            event=event, updated_by_id=actor.id, created_at=now, updated_at=now, **values
        )
        audit.created("communication", row)

        return row

    before = audit.fields_of(existing)
    for field, value in values.items():
        setattr(existing, field, value)
    existing.updated_by_id = actor.id
    existing.updated_at = now
    existing.save()
    audit.updated("communication", existing, before)

    return existing


def clear_template(event: str) -> None:
    for row in PlatformWhatsappTemplate.objects.filter(event=event):
        audit.deleted("communication", row)
        row.delete()
