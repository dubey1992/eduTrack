"""The SMTP server the platform sends through - Super Admin only
(docs/communication.md).

Three endpoints: read the settings (the password is never in the answer,
only whether one is set), save them, and send a test email through them.
The test runs in the request rather than on the queue on purpose: the
administrator is sitting there waiting to learn whether the settings work,
and the answer is the mail server's own words.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..errors import MailTestFailed
from ..policies import MailSettingPolicy, authorize
from ..requests import SendTestEmailRequest, UpdateMailSettingRequest
from ..resources import mail_setting_resource
from ..services import MailSettingService


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def settings(request) -> Response:
    authorize(MailSettingPolicy.manage(request.user))

    if request.method == "GET":
        return Response(mail_setting_resource(MailSettingService.current()))

    form = UpdateMailSettingRequest(data=request.data)
    form.is_valid(raise_exception=True)

    return Response(mail_setting_resource(MailSettingService.save(form.validated_data, request.user)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def test(request) -> Response:
    authorize(MailSettingPolicy.manage(request.user))

    form = SendTestEmailRequest(data=request.data)
    form.is_valid(raise_exception=True)

    row = MailSettingService.current()

    if row is None:
        raise MailTestFailed("Save the SMTP settings before sending a test email.")

    try:
        MailSettingService.test(row, form.validated_data["to"], request.user)
    except MailTestFailed:
        raise
    except Exception as error:
        raise MailTestFailed(f"The mail server refused the test email: {str(error)[:200]}")

    return Response({"message": f"A test email was sent to {form.validated_data['to']}.", "settings": mail_setting_resource(row)})
