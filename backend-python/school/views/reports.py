"""The four reports, as JSON for the screen or CSV for a spreadsheet.

Port of ReportController. Both formats carry the same figures, built by the
same report. Who may see what is decided here rather than in a policy: these
are not records with owners, and each report simply has its own audience.

Checks run in Laravel's order - the form first, then the role - so a teacher
sending a malformed range gets the 422 Laravel gives, not a 403.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import csv_export
from ..enums import UserRole
from ..models import Department, School
from ..policies import authorize
from ..reports import StaffAttendanceReport, StudentAttendanceReport, TeachingCoverageReport, TransportUsageReport
from ..reports.group import build_group
from ..reports.range import ReportRange
from ..requests import ReportRequest
from ..scope import SchoolScope

ADMINS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def student_attendance(request):
    return respond(request, StudentAttendanceReport(), "student-attendance", ADMINS)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def staff_attendance(request):
    # The Accountant reads it too: it is the register payroll is computed from.
    return respond(request, StaffAttendanceReport(), "staff-attendance", (*ADMINS, UserRole.HOD, UserRole.ACCOUNTANT))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def teaching_coverage(request):
    return respond(request, TeachingCoverageReport(), "teaching-coverage", (*ADMINS, UserRole.HOD))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def transport_usage(request):
    return respond(request, TransportUsageReport(), "transport-usage", (*ADMINS, UserRole.TRANSPORT_MANAGER))


def respond(request, report, name: str, roles):
    actor = request.user
    form = ReportRequest(data=request.query_params.dict(), actor=actor)
    form.is_valid(raise_exception=True)

    authorize(actor.role in roles)

    filters = filters_for(actor, form.validated_data)
    scope = SchoolScope.for_actor(actor)

    # `$request->integer('school_id') ?: null`, then a branch outside the
    # actor's reach is ignored rather than refused, like every other school
    # filter in the app. Validation has already made it a number or nothing.
    requested = int(form.initial_data["school_id"]) if form.initial_data.get("school_id") is not None else None
    requested = requested or None
    requested = requested if scope.allows(requested) else None

    # A Group Admin who names no reachable branch means the whole group;
    # everybody else is reporting on exactly one school.
    if requested is None and scope.covers_a_group():
        schools = School.objects.filter(id__in=scope.ids() or []).order_by("name", "id")
        built = build_group(schools, lambda school: single(school.id, report, filters), report)
    else:
        built = single(scope.writable_school_id(requested), report, filters)

    if not form.validated_data["wants_csv"]:
        return Response(built)

    is_group = built.get("group", False)
    start, end = built["range"]["from"], built["range"]["to"]
    rows = report.csv_rows(built)

    if is_group:
        # A group export says which branch a line came from, or it is a heap.
        rows = [[row["school_name"], *line] for row, line in zip(built["rows"], rows)]

    return csv_export.response(
        f"{name}-group-{start or ''}-to-{end or ''}.csv" if is_group else f"{name}-{start}-to-{end}.csv",
        ["School", *report.headings()] if is_group else report.headings(),
        rows,
    )


def single(school_id: int, report, filters: dict) -> dict:
    return report.build(ReportRange.from_filters(school_id, filters), filters)


def filters_for(actor, validated: dict) -> dict:
    filters = {key: validated[key] for key in ("from", "to", "class_section_id", "department_id") if key in validated}

    # A head of department reports on their own departments, whatever they
    # ask for - the scope is theirs, not the request's.
    if actor.role == UserRole.HOD:
        filters["department_ids"] = list(
            Department.objects.filter(school_id=actor.school_id, hod_user_id=actor.id).values_list("id", flat=True)
        )

    return filters
