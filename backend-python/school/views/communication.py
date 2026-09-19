"""The Communication Center: the message log, its KPI tiles, the templates and
the alert switches.

Port of CommunicationController. Nine endpoints, and the order of checks is
the part most easily got wrong, because it decides which of 403, 404 and 422
a caller sees - and Laravel's order differs from endpoint to endpoint:

- **The log and its tiles** authorize before validating: the form request's
  own `authorize()` runs first, so a teacher with junk filters is a 403.
- **Rewording a template** checks the event *before* anything else - an event
  that does not exist is a 404 even to somebody who may not configure - then
  authorizes, then validates, and only then looks for the school.
- **Saving the settings** authorizes, validates, then looks for the school.
- **Resetting a template** and the two reads take `school_id` from the query
  string only; the writes read it from the body as well.

Which school a screen is about is decided the way Laravel decides it: absent
means the actor's own, anything sent is cast as PHP casts it, and the policy
then says whether that school is theirs.
"""

from __future__ import annotations

from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from rest_framework import status

from ..enums import MessageEvent, MessageStatus
from ..errors import GatewayTestFailed, MessageNotRetryable
from ..models import Message, School
from ..notifications import settings_for
from ..pagination import LaravelPagination
from ..policies import MessagePolicy, authorize
from ..requests import (
    MessageIndexRequest,
    SendNoticeRequest,
    SendTestMessageRequest,
    UpdateCommunicationSettingRequest,
    UpdateMessageTemplateRequest,
    UpdateWhatsappTemplateRequest,
    php_int,
    requested_school,
)
from ..resources import (
    communication_setting_resource,
    message_resource,
    message_template_resource,
    notice_result_resource,
)
from ..scope import SchoolScope
from ..services import (
    CommunicationSettingService,
    MessageService,
    MessageTemplateService,
    NoticeService,
    WhatsappTemplateService,
)
from ..validation import normalise


def filters_from(request) -> dict:
    authorize(MessagePolicy.view_any(request.user))

    form = MessageIndexRequest(data=request.query_params.dict())
    form.is_valid(raise_exception=True)

    return form.validated_data


def from_query(request):
    """`school_id` off the query string only - the reads and the reset.

    Cast to an int even when absent, as the controller casts it: a Super
    Admin, who has no school, is asking about school 0 - which the policy
    lets through and which has, correctly, no saved settings.
    """
    value = request.query_params.get("school_id")

    return int(request.user.school_id or 0) if value is None else requested_school(request.user, value)


def from_input(request):
    """`school_id` off the body or the query string, the body winning -
    Laravel's `$request->input()`. An empty string is null, as its middleware
    makes it."""
    value = request.data.get("school_id") if "school_id" in request.data else request.query_params.get("school_id")

    return requested_school(request.user, None if value == "" else value)


def event_or_404(event: str) -> str:
    if event not in MessageEvent.values:
        raise Http404

    return event


# -- the log ----------------------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def messages(request) -> Response:
    found = MessageService.visible_to(request.user, filters_from(request))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([message_resource(row) for row in page])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def summary(request) -> Response:
    return Response(MessageService.summary(request.user, filters_from(request)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def message(request, message_id: int) -> Response:
    found = get_object_or_404(Message, pk=message_id)

    authorize(MessagePolicy.view(request.user, found))

    return Response(message_resource(found))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def retry(request, message_id: int) -> Response:
    found = get_object_or_404(Message, pk=message_id)

    authorize(MessagePolicy.retry(request.user, found))

    # Only a failed message: anything else would duplicate what was delivered
    # or fight the worker already holding it.
    if found.status != MessageStatus.FAILED:
        raise MessageNotRetryable("Only a failed message can be sent again.")

    return Response(message_resource(MessageService.retry(found)))


# -- templates --------------------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def templates(request) -> Response:
    school_id = from_query(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    return Response([message_template_resource(row) for row in MessageTemplateService.list_for(school_id)])


@api_view(["PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def template(request, event: str) -> Response:
    event = event_or_404(event)

    if request.method == "DELETE":
        school_id = from_query(request)

        authorize(MessagePolicy.configure(request.user, school_id))

        school = get_object_or_404(School, pk=school_id)
        MessageTemplateService.reset(school.id, event)

        return Response(message_template_resource(MessageTemplateService.row_for(school.id, event)))

    school_id = from_input(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    form = UpdateMessageTemplateRequest(data=request.data, event=event)
    form.is_valid(raise_exception=True)

    if school_id is None:
        raise Http404

    school = get_object_or_404(School, pk=school_id)
    MessageTemplateService.update(school.id, event, form.validated_data["body"], request.user)

    return Response(message_template_resource(MessageTemplateService.row_for(school.id, event)))


# -- the alert switches -----------------------------------------------------


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def settings(request) -> Response:
    if request.method == "PUT":
        return save_settings(request)

    school_id = from_query(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    # Reading never writes a row; a school that has never saved its switches
    # gets the defaults, marked as not yet saved.
    return Response(communication_setting_resource(settings_for(school_id)))


def save_settings(request) -> Response:
    school_id = from_input(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    form = UpdateCommunicationSettingRequest(data=request.data)
    form.is_valid(raise_exception=True)

    if school_id is None:
        raise Http404

    school = get_object_or_404(School, pk=school_id)

    # A singleton per school, so saving it the first time is still a 200:
    # there is no new address to point a client at.
    return Response(
        communication_setting_resource(CommunicationSettingService.update(school.id, form.validated_data))
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def test_gateway(request) -> Response:
    """One message through the school's own provider, now - so an
    administrator finds out whether the account works before a parent does."""
    school_id = from_input(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    form = SendTestMessageRequest(data=request.data)
    form.is_valid(raise_exception=True)

    school = get_object_or_404(School, pk=school_id or 0)
    result = CommunicationSettingService.test(school.id, form.validated_data["channel"], form.validated_data["to"])

    if not result.accepted:
        raise GatewayTestFailed(result.failure_reason or "The provider did not accept the test message.")

    return Response({"message": f"A test message was sent to {form.validated_data['to']}."})


# -- WhatsApp templates -----------------------------------------------------


@api_view(["PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def whatsapp_template(request, event: str) -> Response:
    """Which registered template carries this event on WhatsApp. The same
    checks, in the same order, as rewording the event."""
    event = event_or_404(event)

    if request.method == "DELETE":
        school_id = from_query(request)

        authorize(MessagePolicy.configure(request.user, school_id))

        school = get_object_or_404(School, pk=school_id)
        WhatsappTemplateService.clear(school.id, event)

        return Response(message_template_resource(MessageTemplateService.row_for(school.id, event)))

    school_id = from_input(request)

    authorize(MessagePolicy.configure(request.user, school_id))

    form = UpdateWhatsappTemplateRequest(data=request.data, event=event)
    form.is_valid(raise_exception=True)

    if school_id is None:
        raise Http404

    school = get_object_or_404(School, pk=school_id)
    WhatsappTemplateService.set(school.id, event, form.validated_data, request.user)

    return Response(message_template_resource(MessageTemplateService.row_for(school.id, event)))


# -- notices: messages written by hand --------------------------------------


def notice_school(request, data: dict):
    """The school a notice is written into - the actor's own unless a Super
    Admin names one - and the check that they may write into it."""
    raw = data.get("school_id")
    requested = None if raw in (None, "") else php_int(raw)
    school_id = SchoolScope.for_actor(request.user).writable_school_id(requested)

    authorize(MessagePolicy.send(request.user, school_id))

    return school_id


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def notices(request) -> Response:
    data = normalise(request.data)
    notice_school(request, data)

    form = SendNoticeRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    result = NoticeService.send(form.validated_data, request.user)

    return Response(notice_result_resource(result), status=status.HTTP_202_ACCEPTED if result["queued"] else status.HTTP_201_CREATED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def notice_preview(request) -> Response:
    """How many people a notice would reach, per channel, before it is sent."""
    data = normalise(request.query_params.dict())
    school_id = notice_school(request, data)

    form = SendNoticeRequest(data=data, actor=request.user, preview=True)
    form.is_valid(raise_exception=True)

    result = NoticeService.preview(school_id, form.validated_data)

    return Response(notice_result_resource(result))
