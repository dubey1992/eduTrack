"""Calls from providers, not people (docs/dashboard.md, D2).

No sign-in: Twilio cannot carry one. Instead every call is signed with the
platform account's auth token, and a call whose signature does not match is
refused before anything is read from it.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.parsers import FormParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.decorators import parser_classes

from .. import delivery_reports, platform_messaging
from ..gateways import twilio


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@parser_classes([FormParser])
def twilio_status(request) -> Response:
    """Twilio's StatusCallback: one message's MessageSid and MessageStatus.

    The signature is checked against the address Twilio was told to call,
    not the one this request arrived on - behind the host's rewrites they
    differ, and Twilio signed the first. Answered 204 whether or not the
    message is known, so the endpoint says nothing about which ids exist.
    """
    url = twilio.status_callback_url()
    params = {key: request.data.get(key) for key in request.data.keys()}
    token = platform_messaging.credentials().get("auth_token")

    if url is None or not twilio.signature_matches(url, params, token, request.headers.get("X-Twilio-Signature")):
        return Response(
            {"code": "INVALID_SIGNATURE", "message": "This request is not from the messaging provider.", "details": {}},
            status=403,
        )

    error = params.get("ErrorCode")
    delivery_reports.record(
        params.get("MessageSid"),
        twilio.DELIVERY.get(params.get("MessageStatus") or ""),
        f"Twilio error {error}" if error else None,
    )

    return Response(status=204)
