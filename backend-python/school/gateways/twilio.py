"""Twilio: SMS, and WhatsApp through its Content Templates.

Both go through the same Messages endpoint with HTTP basic auth (the account
SID and its auth token). SMS is `To`, `From` and `Body`. WhatsApp prefixes
both numbers with `whatsapp:` and, because WhatsApp refuses free text the
school starts, sends a `ContentSid` - the template Twilio approved - with its
numbered variables as JSON.

`From` for SMS is the school's Twilio number or, where the country allows
alphanumeric senders, the sender ID from its settings.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json

from django.conf import settings

from . import Result, Template, digits_only
from .http import ProviderError, post

MESSAGES_URL = "https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json"

CREDENTIALS = (
    ("account_sid", "Account SID", False),
    ("auth_token", "Auth token", True),
    ("sms_from", "SMS sender number", False),
    ("whatsapp_from", "WhatsApp sender number", False),
)


def status_callback_url() -> str | None:
    """Where Twilio reports what became of each message (docs/dashboard.md,
    D2). Only a public https address: Twilio cannot call a laptop, and an
    http one would carry the reports in the clear."""
    base = (getattr(settings, "PUBLIC_API_URL", "") or "").rstrip("/")

    return f"{base}/webhooks/twilio/status" if base.startswith("https://") else None


def signature(url: str, params: dict, auth_token: str) -> str:
    """Twilio's request signature: HMAC-SHA1 of the URL followed by every
    POST parameter, name then value, sorted by name - keyed with the auth
    token, base64-encoded. Compared against the X-Twilio-Signature header."""
    payload = url + "".join(f"{name}{params[name]}" for name in sorted(params))
    digest = hmac.new(auth_token.encode("utf-8"), payload.encode("utf-8"), hashlib.sha1).digest()

    return base64.b64encode(digest).decode("ascii")


def signature_matches(url: str, params: dict, auth_token: str | None, given: str | None) -> bool:
    if not auth_token or not given:
        return False

    return hmac.compare_digest(signature(url, params, auth_token), given)


# Twilio's MessageStatus values, as the delivery they report. queued,
# accepted, sending and sent say nothing about the phone, so they are none.
DELIVERY = {
    "delivered": "delivered",
    "read": "read",
    "undelivered": "undelivered",
    "failed": "undelivered",
}


def _deliver(credentials: dict, form: dict) -> Result:
    callback = status_callback_url()
    if callback:
        form = {**form, "StatusCallback": callback}

    sid = credentials.get("account_sid")
    token = credentials.get("auth_token")

    if not sid or not token:
        return Result(accepted=False, failure_reason="Twilio account SID and auth token are not set up.")

    try:
        answer = post(MESSAGES_URL.format(sid=sid), form=form, basic=(sid, token))
    except ProviderError as error:
        return Result(accepted=False, failure_reason=str(error)[:255])

    if answer["_status"] in (200, 201) and answer.get("sid"):
        return Result(accepted=True, provider_message_id=str(answer["sid"]))

    reason = answer.get("message") or f"Twilio answered {answer['_status']}."

    return Result(accepted=False, failure_reason=f"Twilio: {reason}"[:255])


class TwilioSmsGateway:
    name = "twilio"
    label = "Twilio"
    delivers = True
    CREDENTIALS = CREDENTIALS[:3]

    def send(self, mobile: str, body: str, sender_id: str | None = None, credentials: dict | None = None) -> Result:
        credentials = credentials or {}
        sender = credentials.get("sms_from") or sender_id

        if not sender:
            return Result(accepted=False, failure_reason="No Twilio sender number or sender ID is set up.")

        return _deliver(credentials, {"To": digits_only(mobile), "From": sender, "Body": body})


class TwilioWhatsAppGateway:
    name = "twilio"
    label = "Twilio"
    delivers = True
    CREDENTIALS = (CREDENTIALS[0], CREDENTIALS[1], CREDENTIALS[3])

    def send_template(self, mobile: str, template: Template, credentials: dict | None = None) -> Result:
        credentials = credentials or {}
        sender = credentials.get("whatsapp_from")

        if not sender:
            return Result(accepted=False, failure_reason="No Twilio WhatsApp sender number is set up.")

        variables = {str(position): value for position, value in enumerate(template.values, start=1)}

        return _deliver(
            credentials,
            {
                "To": "whatsapp:" + digits_only(mobile),
                "From": "whatsapp:" + digits_only(sender),
                "ContentSid": template.name,
                "ContentVariables": json.dumps(variables),
            },
        )
