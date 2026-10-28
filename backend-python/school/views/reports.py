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

from .. import csv_export, modules, permissions
from ..clock import DATE_TIME, SchoolClock
from ..enums import UserRole
from ..models import ClassSection, Department, School
from ..errors import ModuleDisabled
from ..policies import FeePolicy, PayrollPolicy, authorize, permitted
from ..reports import (
    ClassPerformanceReport,
    FeeCollectionReport,
    FeeConcessionsReport,
    FeeOutstandingReport,
    LeaveUsageReport,
    PayrollSummaryReport,
    StaffAttendanceReport,
    StudentAttendanceReport,
    StudentPerformanceReport,
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
from ..services import php_number

ADMINS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)

# The fee reports have no fixed list of roles: whoever the matrix lets read
# fees reads them (docs/fees.md) - the office out of the box, a clerk a
# school widens it to - and the Super Admin, who reads every school's fees.
FEES = None


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


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def student_performance(request):
    # A head of department reads it for their own subjects; a class teacher
    # reaches the same figures one child at a time on the student's page.
    return respond(request, StudentPerformanceReport(), "student-performance", (*ADMINS, UserRole.HOD))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def class_performance(request):
    return respond(request, ClassPerformanceReport(), "class-performance", (*ADMINS, UserRole.HOD))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def fee_collection(request):
    return respond(request, FeeCollectionReport(), "fee-collection", FEES, module="fees")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def fee_outstanding(request):
    return respond(request, FeeOutstandingReport(), "fee-outstanding", FEES, module="fees")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def fee_concessions(request):
    return respond(request, FeeConcessionsReport(), "fee-concessions", FEES, module="fees")


def respond(request, report, name: str, roles, module: str | None = None):
    """`roles` None means the module's own row in the matrix decides who
    reads it; `module` names a switchable module the report belongs to, so a
    school without it gets 403 MODULE_DISABLED and a group report covers only
    the branches that have it on."""
    actor = request.user
    form = ReportRequest(data=request.query_params.dict(), actor=actor)
    form.is_valid(raise_exception=True)

    # The matrix says whether the role reads reports at all; which reports
    # a role reads stays per report, since a payroll summary is not a thing
    # every reader of attendance should see.
    allowed = roles is None or actor.role in roles
    authorize(permitted(actor, "reports", school_id=form.validated_data.get("school_id")) and allowed)

    if module is not None:
        authorize(permissions.may_view(actor, module))

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

        if module is not None:
            # Only the branches that use the module; none at all is the
            # module being off, as for one school.
            schools = [school for school in schools if modules.is_enabled(school.id, module)]

            if not schools:
                raise ModuleDisabled(modules.get(module).label)

        built = build_group(schools, lambda school: single(school.id, report, filters, compare), report)
    else:
        school_id = scope.writable_school_id(requested)

        if module == "fees":
            authorize(FeePolicy.view(actor, school_id))

        built = single(school_id, report, filters, compare)

    if form.validated_data["format"] == "json":
        return Response(built)

    if form.validated_data["format"] == "pdf":
        covered = [school_id] if school_id is not None else scope.ids()
        return pdf_response(report, name, built, actor, school_id, filter_labels(form.validated_data, covered))

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


def filter_labels(validated: dict, school_ids: list[int] | None) -> list[tuple[str, str]]:
    """What was asked for, in the words the screen uses for it.

    Printed across the top of the PDF, because a sheet narrowed to one
    class or to the students under 40% is otherwise indistinguishable from
    the whole school's - and it is the whole school's that somebody will
    take it for.

    Looked up only among the schools the report covers ([school_ids]; None
    for a Super Admin, who covers all): a class of another school named in
    the filter matches no rows, and must not lend the sheet its name either.
    """
    labels = []
    sections = ClassSection.objects.select_related("school_class")
    departments = Department.objects.all()

    if school_ids is not None:
        sections = sections.filter(school_class__school_id__in=school_ids)
        departments = departments.filter(school_id__in=school_ids)

    if validated.get("class_section_id"):
        section = sections.filter(pk=validated["class_section_id"]).first()
        if section is not None:
            labels.append(("Class", f"{section.school_class.name} {section.name}"))

    if validated.get("department_id"):
        department = departments.filter(pk=validated["department_id"]).first()
        if department is not None:
            labels.append(("Department", department.name))

    if validated.get("below") is not None:
        labels.append(("Below", f"{php_number(float(validated['below']))}%"))

    return labels


def pdf_response(report, name: str, built: dict, actor, school_id: int | None,
                 filters: list | None = None) -> HttpResponse:
    if school_id is None:
        school_label = f"All {len(built['branches'])} branches"
        clock = SchoolClock.for_user(actor)
    else:
        school_label = School.objects.get(pk=school_id).name
        clock = SchoolClock.for_school(school_id)

    document = pdf.render(
        report, built, school_label=school_label, generated_at=clock.format(clock.now(), DATE_TIME), filters=filters
    )

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
