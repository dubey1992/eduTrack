"""The HOD department report.

Port of HodReportController: one month of a department's teaching, computed
on the fly. The arithmetic lives in HodReportService; this module decides
which school, which department and which month the question is about.

Checks run in Laravel's order, because the order decides which of 422, 403
and 404 a caller sees: the form validates first, then the role gate, then the
per-department check once the department is loaded.

The month defaults to the current month *at the school*: a school in Asia
already in October while the server's clock is still in September is asking
about October.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import SchoolClock
from ..models import Department, School
from ..pagination import resolve_page, resolve_per_page
from ..policies import DepartmentPolicy, authorize
from ..requests import HodDepartmentReportRequest, as_id
from ..scope import SchoolScope
from ..services import HodReportService


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def department_report(request) -> Response:
    form = HodDepartmentReportRequest(data=request.query_params.dict(), actor=request.user)
    form.is_valid(raise_exception=True)

    authorize(DepartmentPolicy.view_any_report(request.user))

    # `$request->integer('school_id') ?: null` - junk and 0 both mean "not
    # asked", and an actor pinned to one school gets that school regardless.
    requested = as_id(request.query_params.get("school_id")) or None
    school = get_object_or_404(
        School, pk=SchoolScope.for_actor(request.user).writable_school_id(requested)
    )

    department = None

    if form.validated_data.get("department_id") is not None:
        department = get_object_or_404(Department, pk=form.validated_data["department_id"])

        authorize(DepartmentPolicy.view_report(request.user, department))

    month = form.validated_data.get("month") or SchoolClock.for_school(school).now().strftime("%Y-%m")

    per_page = (
        resolve_per_page(request.query_params["per_page"])
        if "per_page" in request.query_params
        else 20
    )

    return Response(
        HodReportService.department_report(
            request.user,
            school,
            department,
            month,
            resolve_page(request.query_params.get("page")),
            per_page,
        )
    )
