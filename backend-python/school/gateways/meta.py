"""Meta's WhatsApp Cloud API - straight to WhatsApp, no reseller.

A school needs a Meta Business account, a WhatsApp phone number registered
there (its "phone number ID") and a permanent access token for a system
user. Messages the school starts must be templates Meta approved, named and
in the language they were approved in, with their body parameters in order.
"""

from __future__ import annotations

from . import Result, Template, digits_only
from .http import ProviderError, post

GRAPH_URL = "https://graph.facebook.com/v21.0/{phone_number_id}/messages"


class MetaWhatsAppGateway:
    name = "meta"
    label = "Meta WhatsApp Cloud API"
    delivers = True
    CREDENTIALS = (
        ("phone_number_id", "Phone number ID", False),
        ("access_token", "Access token", True),
    )

    def send_template(self, mobile: str, template: Template, credentials: dict | None = None) -> Result:
        credentials = credentials or {}
        phone_number_id = credentials.get("phone_number_id")
        token = credentials.get("access_token")

        if not phone_number_id or not token:
            return Result(accepted=False, failure_reason="Meta phone number ID and access token are not set up.")

        components = []

        if template.values:
            components.append(
                {"type": "body", "parameters": [{"type": "text", "text": value} for value in template.values]}
            )

        body = {
            "messaging_product": "whatsapp",
            # Meta wants the number without the plus.
            "to": digits_only(mobile).lstrip("+"),
            "type": "template",
            "template": {"name": template.name, "language": {"code": template.language}, "components": components},
        }

        try:
            answer = post(GRAPH_URL.format(phone_number_id=phone_number_id), body=body, bearer=token)
        except ProviderError as error:
            return Result(accepted=False, failure_reason=str(error)[:255])

        messages = answer.get("messages") or []

        if answer["_status"] == 200 and messages and messages[0].get("id"):
            return Result(accepted=True, provider_message_id=str(messages[0]["id"]))

        error = answer.get("error") or {}
        reason = error.get("message") or f"Meta answered {answer['_status']}."

        return Result(accepted=False, failure_reason=f"Meta: {reason}"[:255])
