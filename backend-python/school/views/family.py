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

Fees (F3), read only - the app takes no payments:
- GET  family/children/{id}/fees - instalments, totals, receipts, credit, how to pay
- GET  family/children/{id}/fees/statement.pdf - the year's statement
- GET  family/children/{id}/receipts/{receipt_id}/pdf - one receipt; another
  child's receipt is a 404

The bus (F4):
- GET  family/children/{id}/bus - route, stop, vehicle, contacts, today's trips
- GET  family/children/{id}/bus/live - where the bus is, only while the
  child's own trip runs (BUS_NOT_LIVE otherwise)
- GET  family/maps-config - the map key, as maps/config gives staff

Talking to the school (F5):
- GET  family/children/{id}/absence-notes - the child's notes, newest first
- POST family/children/{id}/absence-notes - a new one (multipart when a
  photo of a doctor's note is attached)
- GET  family/children/{id}/call-requests - their "please call me"s
- POST family/children/{id}/call-requests - {recipient, reason, preferred_time?}
- POST family/notices/{id}/reply - {student_id, answer, note?}: Yes or No to a
  notice that asks, for one of their children it is about
"""

from __future__ import annotations

import re

from django.conf import settings
from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .. import (
    absence_notes,
    call_requests,
    family_bus,
    family_day,
    family_fees,
    family_homework,
    family_inbox,
    family_learning,
    modules,
    notice_replies,
)
from ..clock import SchoolClock
from ..enums import UserRole
from ..errors import BusNotLive, ModuleDisabled, NotAFamilyAccount, ProgressReportNotReady
from ..fees import receipt_pdf, statement_pdf
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
    children = list(FamilyAuthService.children_of(user))

    def with_reply(message) -> dict:
        """A notice that asks parents carries its question and their answers (F5)."""
        item = family_notice_resource(message)
        item["reply"] = (
            notice_replies.reply_block(message.announcement, children) if message.announcement_id else None
        )
        return item

    response = paginator.get_paginated_response([with_reply(message) for message in page])
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
    # The evening homework message (M8, 8.1).
    homework = serializers.BooleanField(required=False)


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


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_homework(request, child_id: int) -> Response:
    """The child's class's homework over the last two weeks (M8, 8.1)."""
    user = family_reader(request)

    return Response(family_homework.homework_for(child_of(user, child_id)))


# -- Fees (F3) -------------------------------------------------------------------


def fees_reader(request):
    """A family account reading fees: the Fees module must be on as well as
    the Family App - a school without it has nothing to show."""
    user = family_reader(request)

    if not modules.is_enabled(user.school_id, family_fees.MODULE):
        raise ModuleDisabled(modules.get(family_fees.MODULE).label)

    return user


def pdf_response(document: bytes, file_name: str) -> HttpResponse:
    response = HttpResponse(document, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{file_name}"'
    return response


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_fees(request, child_id: int) -> Response:
    user = fees_reader(request)
    return Response(family_fees.fees_of(child_of(user, child_id)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_fee_statement(request, child_id: int):
    user = fees_reader(request)
    found = family_fees.statement_of(child_of(user, child_id))

    if found is None:
        raise Http404()

    return pdf_response(statement_pdf.render(found), statement_pdf.file_name(found["student"], found["year"]))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_receipt_pdf(request, child_id: int, receipt_id: int):
    user = fees_reader(request)
    receipt = family_fees.receipt_of(child_of(user, child_id), receipt_id)

    if receipt is None:
        raise Http404()

    return pdf_response(receipt_pdf.render(receipt), receipt_pdf.file_name(receipt))


# -- The bus (F4) -----------------------------------------------------------------


def transport_reader(request):
    """A family account reading the bus: Transport must be on as well."""
    user = family_reader(request)

    if not modules.is_enabled(user.school_id, family_bus.MODULE):
        raise ModuleDisabled(modules.get(family_bus.MODULE).label)

    return user


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_bus(request, child_id: int) -> Response:
    user = transport_reader(request)
    found = family_bus.bus_of(child_of(user, child_id))

    if found is None:
        raise Http404()

    return Response(found)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_bus_live(request, child_id: int) -> Response:
    user = transport_reader(request)
    found = family_bus.live_of(child_of(user, child_id))

    if found is None:
        raise BusNotLive()

    return Response(found)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def maps_config(request) -> Response:
    """The browser map key for the Family app, as maps/config gives staff.
    Public by nature - any map on the web carries its key - and restricted
    by referrer and package in Google Cloud."""
    family_reader(request)
    key = (settings.GOOGLE_MAPS_BROWSER_KEY or "").strip()

    return Response({"available": bool(key), "browser_key": key})


# -- Absence notes (F5) ----------------------------------------------------------


class AbsenceNoteRequest(serializers.Serializer):
    start_date = serializers.DateField(error_messages={"invalid": "Choose the first day.", "required": "Choose the first day."})
    end_date = serializers.DateField(error_messages={"invalid": "Choose the last day.", "required": "Choose the last day."})
    reason = serializers.CharField(max_length=2000, allow_blank=True, trim_whitespace=True)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def child_absence_notes(request, child_id: int) -> Response:
    user = family_reader(request)
    child = child_of(user, child_id)

    if request.method == "GET":
        return Response({"data": [absence_notes.note_resource(n) for n in absence_notes.for_family(child)]})

    form = AbsenceNoteRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    note = absence_notes.send(child, user, data["start_date"], data["end_date"], data["reason"],
                              photo=request.FILES.get("photo"))

    return Response(absence_notes.note_resource(note), status=status.HTTP_201_CREATED)


# -- "Please call me" and replies to notices (F5) ------------------------------------


class CallRequestRequest(serializers.Serializer):
    recipient = serializers.CharField(max_length=20)
    reason = serializers.CharField(max_length=2000, allow_blank=True)
    preferred_time = serializers.CharField(max_length=500, required=False, allow_blank=True, allow_null=True)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def child_call_requests(request, child_id: int) -> Response:
    user = family_reader(request)
    child = child_of(user, child_id)

    if request.method == "GET":
        rows = child.call_requests.order_by("-created_at", "-id")[:20]
        return Response({"data": [call_requests.request_resource(row) for row in rows]})

    form = CallRequestRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    made = call_requests.ask(child, user, data["recipient"], data["reason"], data.get("preferred_time"))

    return Response(call_requests.request_resource(made), status=status.HTTP_201_CREATED)


class NoticeReplyRequest(serializers.Serializer):
    student_id = serializers.IntegerField()
    answer = serializers.BooleanField()
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True, allow_null=True)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def notice_reply(request, notice_id: int) -> Response:
    user = family_reader(request)
    # Their own inbox copy of the notice; anybody else's is a 404.
    message = get_object_or_404(MessageService.inbox(user, None).select_related("announcement"), pk=notice_id)
    form = NoticeReplyRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    if message.announcement_id is None:
        raise Http404()

    children = list(FamilyAuthService.children_of(user))
    asked = {child.id: child for child in notice_replies.children_asked(message.announcement, children)}
    child = asked.get(data["student_id"])
    if child is None:
        raise Http404()

    notice_replies.answer(message.announcement, child, user, data["answer"], data.get("note"))

    return Response(notice_replies.reply_block(message.announcement, children))


# -- Admit cards (docs/examinations.md) ---------------------------------------------


def exams_reader(request):
    """A family account reading exams: Class Tests must be on as well."""
    user = family_reader(request)

    if not modules.is_enabled(user.school_id, "assessments"):
        raise ModuleDisabled(modules.get("assessments").label)

    return user


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_admit_cards(request, child_id: int) -> Response:
    """The published exams the child's class sits, newest year first, each
    saying whether the card can be downloaded. A withheld card says to
    contact the school - never why."""
    from ..examinations.resources import family_card_resource
    from ..examinations.service import card_state, class_of, latest_version
    from ..models import Examination, StudentEnrollment

    child = child_of(exams_reader(request), child_id)
    year_ids = StudentEnrollment.objects.filter(student_id=child.id).values_list("academic_year_id", flat=True)
    exams = (
        Examination.objects.filter(school_id=child.school_id, version__gt=0, academic_year_id__in=list(year_ids))
        .select_related("academic_year", "academic_term")
        .order_by("-academic_year__start_date", "-published_at", "id")
    )
    today = SchoolClock.for_school(child.school_id).now().date()
    cards = []

    for exam in exams:
        state = card_state(exam, child, today)

        if state.code != "no_papers":
            cards.append(family_card_resource(exam, state, latest_version(exam), class_of(child, exam.academic_year_id)))

    return Response({"data": cards})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def child_admit_card_pdf(request, child_id: int, exam_id: int):
    """The child's card for one published exam, from its latest version.
    Another school's exam, or one the child does not sit, is a 404."""
    from ..examinations import card_pdf
    from ..examinations.service import card_state, class_of, latest_version, require_ready
    from ..models import Examination

    child = child_of(exams_reader(request), child_id)
    exam = get_object_or_404(
        Examination.objects.select_related("academic_year", "school"), pk=exam_id, school_id=child.school_id,
        version__gt=0,
    )
    today = SchoolClock.for_school(child.school_id).now().date()
    state = card_state(exam, child, today)

    if state.code in ("no_papers", "not_published"):
        raise Http404()

    require_ready(state)
    version = latest_version(exam)
    card = card_pdf.Card(
        student=child, snapshot=version.snapshot, class_id=class_of(child, exam.academic_year_id),
        version=version.version, issued_on=SchoolClock.for_school(child.school_id).format(version.published_at, "m/d/Y"),
    )
    document = card_pdf.render([card], school=exam.school, year_id=exam.academic_year_id)

    return pdf_response(document, card_pdf.file_name(exam.name, child.admission_number or child.id))
