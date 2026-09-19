"""The daily register.

Port of AttendanceController. Four endpoints on two paths, because the client
asks about a class and a day rather than about a record: `GET /attendance`
lists marks, and `/attendance/register` is the screen a teacher actually uses.

`class_section_id` arrives in the body rather than the path on purpose. A bad
id fails validation with a 422, and ownership is only checked once the section
is known to be real - a 403 about a section that does not exist would tell the
caller it does.

Submitting and correcting are separate actions. POST refuses a class and day
that already has a register, so a duplicate tap cannot silently overwrite a
different set of marks; PATCH is the deliberate correction.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import SchoolClock
from ..enums import UserRole
from ..models import Attendance, ClassSection
from ..pagination import LaravelPagination
from ..policies import ClassSectionPolicy, authorize, permitted
from ..requests import AttendanceRegisterRequest, MarkAttendanceRequest
from ..resources import attendance_resource
from ..services import AttendanceService

ADMIN_AND_TEACHER = (
    UserRole.SUPER_ADMIN,
    UserRole.GROUP_ADMIN,
    UserRole.SCHOOL_ADMIN,
    UserRole.TEACHER,
)


def school_today(request):
    """Today, at the school the actor is acting for.

    Passed into the form so a date is judged against the school's calendar
    rather than the server's - a teacher in Asia/Kolkata marking the register
    at 7am is ahead of UTC, and the server would otherwise call an ordinary
    morning the future.
    """
    clock = SchoolClock.for_scope(request.user, request.data.get("school_id"))

    return {"school_today": clock.now().date()}


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def register(request) -> Response:
    form = AttendanceRegisterRequest(
        data=request.query_params.dict(),
        context={"school_today": SchoolClock.for_scope(request.user, None).now().date()},
    )
    form.is_valid(raise_exception=True)

    section = section_for(form.validated_data["class_section_id"])

    authorize(ClassSectionPolicy.view_attendance(request.user, section))

    return Response(AttendanceService.register(section, form.validated_data["date"]))


@api_view(["GET", "POST", "PATCH"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return mark(request, correcting=False)

    if request.method == "PATCH":
        return mark(request, correcting=True)

    # The matrix says who reads attendance; the service narrows the rows.
    authorize(permitted(request.user, "attendance", school_id=request.query_params.get("school_id") or None))

    marks = AttendanceService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "class_section_id": request.query_params.get("class_section_id"),
            "student_id": request.query_params.get("student_id"),
            "status": request.query_params.get("status"),
            "date_from": request.query_params.get("date_from"),
            "date_to": request.query_params.get("date_to"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(marks, request)

    return paginator.get_paginated_response([attendance_resource(row) for row in page])


def mark(request, correcting: bool) -> Response:
    form = MarkAttendanceRequest(data=request.data, context=school_today(request))
    form.is_valid(raise_exception=True)

    section = section_for(form.validated_data["class_section_id"])

    authorize(ClassSectionPolicy.mark_attendance(request.user, section))

    if correcting:
        body = AttendanceService.update(section, form.validated_data, request.user)

        return Response(body)

    body = AttendanceService.submit(section, form.validated_data, request.user)

    return Response(body, status=status.HTTP_201_CREATED)


def section_for(class_section_id: int) -> ClassSection:
    return get_object_or_404(
        ClassSection.objects.select_related("school_class"), pk=class_section_id
    )
