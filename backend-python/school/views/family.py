"""The Family app's own API (docs/parent-student-app.md, F0). Everything here
lives under /api/v1/family/, the only part of the API a family account can
reach (school/authentication.py).

Sign-in (no token yet, throttled):
- POST family/auth/setup - mobile + the setup code from the school's letter +
  a new 6-digit passcode registers this phone; answers with a session token
  and the device secret.
- POST family/auth/login - mobile + passcode + that device secret.

Signed in:
- GET  family/me - who they are, their school, and the children they see.
- POST family/auth/logout - ends this session.

The parent's screens (F1, read only), each about one of their own children;
another child's id is a 404, the same as one that does not exist:
- GET  family/children/{id}/today
- GET  family/children/{id}/attendance?month=YYYY-MM
- GET  family/calendar?month=YYYY-MM - the school's holidays
- GET  family/notices[?unread=1] - the school's messages to them, newest first
- POST family/notices/{id}/read, family/notices/read-all
- GET/PATCH family/notification-settings - their per-kind switches
- POST/DELETE family/devices - this phone, for push

Learning (F2):
- GET  family/children/{id}/results[?term_id=] - published tests, term by term
- GET  family/children/{id}/progress-report[?term_id=] - the PDF, once the term is over
- GET  family/children/{id}/timetable - the class's week
- GET  family/children/{id}/syllabus - topics covered per subject
"""

from __future__ import annotations

import re

from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .. import family_day, family_inbox, family_learning
from ..clock import SchoolClock
from ..enums import UserRole
from ..errors import NotAFamilyAccount, ProgressReportNotReady
from ..family_accounts import FamilyAuthService, assert_family_app_on
from ..family_requests import FamilyLoginRequest, FamilySetupRequest
from ..family_resources import family_me_resource, family_notice_resource
from ..pagination import LaravelPagination
from ..services import MessageService
from ..throttling import FamilyAddressThrottle, FamilyThrottle


def user_agent(request) -> str | None:
    return request.META.get("HTTP_USER_AGENT")


def family_user(request):
    """The signed-in family account. A staff session never reaches the
    Family app's data, any more than a family session reaches staff data."""
    if not UserRole.is_family(request.user.role):
        raise NotAFamilyAccount()

    return request.user


def family_reader(request):
    """A family account reading its school's data: the Family App module
    must still be on - switched off, the app stops showing anything."""
    user = family_user(request)
    assert_family_app_on(user.school_id)

    return user


def child_of(user, child_id: int):
    """One of the caller's own children. Anybody else's is a 404, never a
    403: the answer does not confirm that the child exists."""
    return get_object_or_404(FamilyAuthService.children_of(user), pk=child_id)


MONTH = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")


def month_of(request, school_id) -> tuple[int, int]:
    """?month=YYYY-MM, or this month at the school."""
    raw = request.query_params.get("month")

    if raw is None:
        today = SchoolClock.for_school(school_id).now().date()
        return today.year, today.month

    found = MONTH.match(raw)
    if found is None:
        raise serializers.ValidationError({"month": ["The month must be written as YYYY-MM, e.g. 2026-11."]})

    return int(found.group(1)), int(found.group(2))


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([FamilyThrottle, FamilyAddressThrottle])
def setup(request) -> Response:
    form = FamilySetupRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token, secret = FamilyAuthService.setup(
        data["mobile"], data["setup_code"], data["passcode"], data.get("device_name"), user_agent(request)
    )

    # The device secret is in this answer and nowhere else, ever.
    return Response(
        {"token": token, "device_secret": secret, "me": family_me_resource(user, FamilyAuthService.children_of(user))},
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([FamilyThrottle, FamilyAddressThrottle])
def login(request) -> Response:
    form = FamilyLoginRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token = FamilyAuthService.login(data["mobile"], data["passcode"], data["device_secret"], user_agent(request))

    return Response({"token": token, "me": family_me_resource(user, FamilyAuthService.children_of(user))})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me(request) -> Response:
    user = family_user(request)

    return Response(family_me_resource(user, FamilyAuthService.children_of(user)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request) -> Response:
    family_user(request)
    request.auth.delete()

    return Response(status=status.HTTP_204_NO_CONTENT)


# -- the parent's screens (F1) ---------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_today(request, child_id: int) -> Response:
    user = family_reader(request)

    return Response(family_day.today_for(child_of(user, child_id)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_attendance(request, child_id: int) -> Response:
    user = family_reader(request)
    child = child_of(user, child_id)
    year, month = month_of(request, child.school_id)

    return Response(family_day.month_for(child, year, month))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def school_calendar(request) -> Response:
    user = family_reader(request)
    year, month = month_of(request, user.school_id)

    return Response(family_day.calendar_for(user.school_id, year, month))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def notices(request) -> Response:
    user = family_reader(request)
    found = MessageService.inbox(user, request.query_params.get("unread"))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)
    response = paginator.get_paginated_response([family_notice_resource(message) for message in page])
    response.data["unread_count"] = MessageService.unread_count(user)

    return response


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def notice_read(request, notice_id: int) -> Response:
    user = family_reader(request)
    # Only the caller's own inbox: anybody else's message is a 404.
    message = get_object_or_404(MessageService.inbox_of(user), pk=notice_id)

    return Response(family_notice_resource(MessageService.mark_read(message)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def notices_read_all(request) -> Response:
    user = family_reader(request)

    return Response({"marked": MessageService.mark_all_read(user)})


class NotificationSettingsRequest(serializers.Serializer):
    attendance = serializers.BooleanField(required=False)
    transport = serializers.BooleanField(required=False)
    fee = serializers.BooleanField(required=False)
    result = serializers.BooleanField(required=False)
    notices = serializers.BooleanField(required=False)


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def notification_settings(request) -> Response:
    user = family_reader(request)

    if request.method == "GET":
        return Response(family_inbox.settings_of(user))

    form = NotificationSettingsRequest(data=request.data)
    form.is_valid(raise_exception=True)

    return Response(family_inbox.save_settings(user, form.validated_data))


# -- learning (F2) ---------------------------------------------------------------


def term_id_of(request) -> int | None:
    raw = request.query_params.get("term_id")
    if raw is None:
        return None

    if not raw.isdigit():
        raise serializers.ValidationError({"term_id": ["The term must be a number."]})

    return int(raw)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_results(request, child_id: int) -> Response:
    user = family_reader(request)

    return Response(family_learning.results_for(child_of(user, child_id), term_id_of(request)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_progress_report(request, child_id: int):
    user = family_reader(request)
    found = family_learning.progress_report_of(child_of(user, child_id), term_id_of(request))

    if found is None:
        raise ProgressReportNotReady()

    document, file_name = found
    response = HttpResponse(document, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{file_name}"'
    return response


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_timetable(request, child_id: int) -> Response:
    user = family_reader(request)

    return Response(family_learning.timetable_for(child_of(user, child_id)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_syllabus(request, child_id: int) -> Response:
    user = family_reader(request)

    return Response(family_learning.syllabus_for(child_of(user, child_id)))
