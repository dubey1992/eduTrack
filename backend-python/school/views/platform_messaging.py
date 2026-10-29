"""School365ai's own SMS and WhatsApp account - Super Admin only
(docs/platform-messaging.md, M1).

Every school's messages go out through it. Read it (no secret is ever in
the answer, only whether each key is set), save it, send a test through it,
and map the WhatsApp templates School365ai has had approved to the events
they carry.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import platform_messaging
from ..enums import MessageChannel
from ..errors import GatewayTestFailed
from ..policies import MailSettingPolicy, authorize
from ..requests import SendTestMessageRequest, UpdatePlatformMessagingRequest, UpdateWhatsappTemplateRequest
from ..resources import platform_messaging_resource
from ..throttling import TestMessageThrottle
from .communication import event_or_404


def _answer() -> Response:
    return Response(platform_messaging_resource(platform_messaging.current()))


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def settings(request) -> Response:
    # The same audience as the SMTP server, the platform's other way out.
    authorize(MailSettingPolicy.manage(request.user))

    if request.method == "PUT":
        form = UpdatePlatformMessagingRequest(data=request.data)
        form.is_valid(raise_exception=True)
        platform_messaging.save(form.validated_data, request.user)

    return _answer()


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([TestMessageThrottle])
def test(request) -> Response:
    authorize(MailSettingPolicy.manage(request.user))

    form = SendTestMessageRequest(data=request.data)
    form.is_valid(raise_exception=True)
    channel = form.validated_data["channel"]
    to = form.validated_data["to"]

    result = platform_messaging.test(channel, to, request.user)

    if not result.accepted:
        raise GatewayTestFailed(result.failure_reason or "The provider refused the test message.")

    label = "SMS" if channel == MessageChannel.SMS else "WhatsApp message"
    note = "" if platform_messaging.sms_delivers() else " The Demo Gateway records it and sends nothing."

    return Response({
        "message": f"A test {label} was sent to {to}.{note}",
        "settings": platform_messaging_resource(platform_messaging.current()),
    })


@api_view(["PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def whatsapp_template(request, event: str) -> Response:
    authorize(MailSettingPolicy.manage(request.user))
    event = event_or_404(event)

    if request.method == "DELETE":
        platform_messaging.clear_template(event)
    else:
        form = UpdateWhatsappTemplateRequest(data=request.data, event=event)
        form.is_valid(raise_exception=True)
        platform_messaging.set_template(event, form.validated_data, request.user)

    return _answer()
