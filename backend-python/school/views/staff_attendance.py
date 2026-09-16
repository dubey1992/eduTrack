"""The staff register.

Port of StaffAttendanceController. The same shape as the student one - a
register screen, a submit, a correct, and a list - with two differences worth
knowing.

**An HOD marks it.** That is the one place in the product an HOD writes
something outside their own record: they run a department and its register is
theirs. Which staff they may mark is narrowed to their own departments, and
the narrowing happens in the service *and* in the form, so a hand-made request
cannot get round the roster.

**Nobody is told.** Staff attendance is a record the school keeps, not news
anybody is waiting for - which is why this module has no notification step and
the student one does.
"""

from __future__ import annotations

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import SchoolClock
from ..pagination import LaravelPagination
from ..policies import StaffAttendancePolicy, authorize
from ..requests import MarkStaffAttendanceRequest, StaffAttendanceRegisterRequest
from ..resources import staff_attendance_resource
from ..scope import SchoolScope
from ..services import StaffAttendanceService


def context_for(request, payload) -> dict:
    """Today, at the school being acted for.

    A Super Admin names the school; everybody else is measured against their
    own, so a date is judged on the calendar of the school it belongs to
    rather than the server's.
    """
    clock = SchoolClock.for_scope(request.user, payload.get("school_id"))

    return {"school_today": clock.now().date()}


def school_for(request, form) -> int:
    """The school this actor is acting for.

    A Super Admin must say; everybody else gets their own whatever they sent.
    """
    return SchoolScope.for_actor(request.user).writable_school_id(
        form.resolved_school_id()
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def register(request) -> Response:
    payload = request.query_params.dict()
    form = StaffAttendanceRegisterRequest(
        data=payload, actor=request.user, context=context_for(request, payload)
    )
    form.is_valid(raise_exception=True)

    school_id = school_for(request, form)

    authorize(StaffAttendancePolicy.manage(request.user, school_id))

    return Response(
        StaffAttendanceService.register(
            school_id,
            form.validated_data.get("department_id"),
            form.validated_data["date"],
            request.user,
        )
    )


@api_view(["GET", "POST", "PATCH"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method in ("POST", "PATCH"):
        return mark(request, correcting=request.method == "PATCH")

    authorize(StaffAttendancePolicy.view_any(request.user))

    marks = StaffAttendanceService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "staff_profile_id": request.query_params.get("staff_profile_id"),
            "department_id": request.query_params.get("department_id"),
            "status": request.query_params.get("status"),
            "date_from": request.query_params.get("date_from"),
            "date_to": request.query_params.get("date_to"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(marks, request)

    return paginator.get_paginated_response(
        [staff_attendance_resource(row) for row in page]
    )


def mark(request, correcting: bool) -> Response:
    form = MarkStaffAttendanceRequest(
        data=request.data, actor=request.user, context=context_for(request, request.data)
    )
    form.is_valid(raise_exception=True)

    school_id = school_for(request, form)

    authorize(StaffAttendancePolicy.manage(request.user, school_id))

    if correcting:
        return Response(
            StaffAttendanceService.update(school_id, form.validated_data, request.user)
        )

    return Response(
        StaffAttendanceService.submit(school_id, form.validated_data, request.user),
        status=status.HTTP_201_CREATED,
    )
