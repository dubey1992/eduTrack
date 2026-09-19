"""The reports, as JSON for the screen, CSV for a spreadsheet or PDF to print.

Port of ReportController, and Phase 20 on top of it: three more reports, the
PDF format and the previous-period comparison, none of which Laravel has.
Every format carries the same figures, built by the same report. Who may see what is decided here rather than in a policy: these
are not records with owners, and each report simply has its own audience.

Checks run in Laravel's order - the form first, then the role - so a teacher
sending a malformed range gets the 422 Laravel gives, not a 403.
"""

from __future__ import annotations

from django.http import HttpResponse
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import csv_export
from ..clock import DATE_TIME, SchoolClock
from ..enums import UserRole
from ..models import Department, School
from ..policies import PayrollPolicy, authorize, permitted
from ..reports import (
    LeaveUsageReport,
    PayrollSummaryReport,
    StaffAttendanceReport,
    StudentAttendanceReport,
    SyllabusProgressReport,
    TeachingCoverageReport,
    TransportUsageReport,
    comparison,
    pdf,
)
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


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def payroll_summary(request):
    # Whoever runs payroll, and the Super Admin, who sees it across schools.
    roles = (UserRole.SUPER_ADMIN, *PayrollPolicy.MANAGERS)
    return respond(request, PayrollSummaryReport(), "payroll-summary", roles)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def leave_usage(request):
    return respond(request, LeaveUsageReport(), "leave-usage", (*ADMINS, UserRole.HOD))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def syllabus_progress(request):
    return respond(request, SyllabusProgressReport(), "syllabus-progress", (*ADMINS, UserRole.HOD))


def respond(request, report, name: str, roles):
    actor = request.user
    form = ReportRequest(data=request.query_params.dict(), actor=actor)
    form.is_valid(raise_exception=True)

    # The matrix says whether the role reads reports at all; which reports
    # a role reads stays per report, since a payroll summary is not a thing
    # every reader of attendance should see.
    authorize(permitted(actor, "reports", school_id=form.validated_data.get("school_id")) and actor.role in roles)

    filters = filters_for(actor, form.validated_data)
    scope = SchoolScope.for_actor(actor)

    # `$request->integer('school_id') ?: null`, then a branch outside the
    # actor's reach is ignored rather than refused, like every other school
    # filter in the app. Validation has already made it a number or nothing.
    requested = int(form.initial_data["school_id"]) if form.initial_data.get("school_id") is not None else None
    requested = requested or None
    requested = requested if scope.allows(requested) else None

    compare = form.validated_data["compare"]
    school_id = None

    # A Group Admin who names no reachable branch means the whole group;
    # everybody else is reporting on exactly one school.
    if requested is None and scope.covers_a_group():
        schools = list(School.objects.filter(id__in=scope.ids() or []).order_by("name", "id"))
        built = build_group(schools, lambda school: single(school.id, report, filters, compare), report)
    else:
        school_id = scope.writable_school_id(requested)
        built = single(school_id, report, filters, compare)

    if form.validated_data["format"] == "json":
        return Response(built)

    if form.validated_data["format"] == "pdf":
        return pdf_response(report, name, built, actor, school_id)

    is_group = built.get("group", False)
    start, end = built["range"]["from"], built["range"]["to"]
    headings = report.headings()
    rows = report.csv_rows(built)

    if is_group:
        # A group export says which branch a line came from, or it is a heap.
        headings = ["School", *headings]
        rows = [[row["school_name"], *line] for row, line in zip(built["rows"], rows)]

    if compare:
        headings = [*headings, *comparison.headings(report)]
        rows = [[*line, *comparison.cells(report, row)] for row, line in zip(built["rows"], rows)]

    return csv_export.response(
        f"{name}-group-{start or ''}-to-{end or ''}.csv" if is_group else f"{name}-{start}-to-{end}.csv",
        headings,
        rows,
    )


def pdf_response(report, name: str, built: dict, actor, school_id: int | None) -> HttpResponse:
    if school_id is None:
        school_label = f"All {len(built['branches'])} branches"
        clock = SchoolClock.for_user(actor)
    else:
        school_label = School.objects.get(pk=school_id).name
        clock = SchoolClock.for_school(school_id)

    document = pdf.render(report, built, school_label=school_label, generated_at=clock.format(clock.now(), DATE_TIME))

    response = HttpResponse(document, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{pdf.file_name(name, built)}"'
    return response


def single(school_id: int, report, filters: dict, compare: bool = False) -> dict:
    report_range = ReportRange.from_filters(school_id, filters)
    built = report.build(report_range, filters)

    if compare:
        # The previous period is everybody, not just those under the
        # threshold now - a student who has only just slipped below it still
        # has last month's rate to be read against.
        earlier = {key: value for key, value in filters.items() if key != "below"}
        comparison.attach(report, built, report.build(report_range.previous(), earlier))

    return built


def filters_for(actor, validated: dict) -> dict:
    filters = {
        key: validated[key] for key in ("from", "to", "class_section_id", "department_id", "below") if key in validated
    }

    # A head of department reports on their own departments, whatever they
    # ask for - the scope is theirs, not the request's.
    if actor.role == UserRole.HOD:
        filters["department_ids"] = list(
            Department.objects.filter(school_id=actor.school_id, hod_user_id=actor.id).values_list("id", flat=True)
        )

    return filters
