"""Payroll (Phase 19): salaries, a month's run, payslips. See docs/payroll.md.

Python only - there is no Laravel twin. Each endpoint loads its record, asks
PayrollPolicy, validates, then hands over to the payroll services, which write
the change and its audit row together.

A record outside the actor's reach is a 403, like every other school-owned
record in this API: the id exists, and it is not theirs.
"""

from __future__ import annotations

from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import PayrollRunStatus, PayslipLineSource
from ..errors import PayrollRunNotFinalized
from ..models import PayrollRun, Payslip, PayslipLine, School, StaffProfile
from ..pagination import LaravelPagination
from ..payroll import payslips
from ..payroll.requests import AdjustmentRequest, GeneratePayrollRunRequest, PayRequest, SaveSalaryRequest
from ..payroll.resources import employee_salary_resource, payslip_resource, run_resource
from ..payroll.service import PayrollRunService, PayslipService, SalaryService, school_today
from ..policies import PayrollPolicy, authorize


def filters_from(request, *names) -> dict:
    return {name: request.query_params.get(name) for name in names}


# -- salaries -----------------------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def salaries(request) -> Response:
    authorize(PayrollPolicy.view_any(request.user))

    found = SalaryService.employees(request.user, filters_from(request, "school_id", "department_id", "search", "salary"))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([employee_salary_resource(profile) for profile in page])


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def salary(request, staff_profile_id: int) -> Response:
    profile = get_object_or_404(
        StaffProfile.objects.select_related("user", "department", "school"), pk=staff_profile_id
    )

    if request.method == "PUT":
        authorize(PayrollPolicy.manage(request.user, profile.school_id))

        form = SaveSalaryRequest(data=request.data)
        form.is_valid(raise_exception=True)

        SalaryService.save(profile, form.validated_data, request.user, request)

    else:
        authorize(PayrollPolicy.view(request.user, profile.school_id))

    profile = StaffProfile.objects.select_related("user", "department", "school", "salary__updated_by").get(pk=profile.pk)

    return Response(employee_salary_resource(profile))


# -- runs ---------------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def runs(request) -> Response:
    if request.method == "POST":
        authorize(PayrollPolicy.manage_any(request.user))

        form = GeneratePayrollRunRequest(data=request.data, actor=request.user, school_today=school_today)
        form.is_valid(raise_exception=True)

        school_id = form.resolved_school_id()
        authorize(PayrollPolicy.manage(request.user, school_id))

        run = PayrollRunService.generate(
            School.objects.get(pk=school_id), form.validated_data["year"], form.validated_data["month"],
            request.user, request,
        )

        return Response(run_detail(run.id), status=status.HTTP_201_CREATED)

    authorize(PayrollPolicy.view_any(request.user))

    found = PayrollRunService.visible_to(request.user, filters_from(request, "school_id", "year", "status"))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)
    figures = PayrollRunService.totals(run.id for run in page)

    return paginator.get_paginated_response([run_resource(run, figures.get(run.id)) for run in page])


@api_view(["GET", "DELETE"])
@permission_classes([IsAuthenticated])
def run(request, run_id: int) -> Response:
    found = load_run(run_id)

    if request.method == "DELETE":
        authorize(PayrollPolicy.manage(request.user, found.school_id))
        PayrollRunService.delete(found, request.user, request)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(PayrollPolicy.view(request.user, found.school_id))

    return Response(run_detail(found.id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def regenerate(request, run_id: int) -> Response:
    found = load_run(run_id)
    authorize(PayrollPolicy.manage(request.user, found.school_id))

    PayrollRunService.regenerate(found, request.user, request)

    return Response(run_detail(found.id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def finalize(request, run_id: int) -> Response:
    found = load_run(run_id)
    authorize(PayrollPolicy.manage(request.user, found.school_id))

    PayrollRunService.finalize(found, request.user, request)

    return Response(run_detail(found.id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def pay_run(request, run_id: int) -> Response:
    found = load_run(run_id)
    authorize(PayrollPolicy.manage(request.user, found.school_id))

    form = PayRequest(data=request.data, school_today=school_today(found.school_id))
    form.is_valid(raise_exception=True)

    PayrollRunService.pay_all(found, form.validated_data, request.user, request)

    return Response(run_detail(found.id))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def run_payslips(request, run_id: int) -> Response:
    found = load_run(run_id)
    authorize(PayrollPolicy.view(request.user, found.school_id))

    slips = found.payslips.select_related("payroll_run", "school").order_by("employee_code", "id")

    if request.query_params.get("status"):
        slips = slips.filter(status=request.query_params["status"])

    if request.query_params.get("search"):
        search = request.query_params["search"]
        slips = slips.filter(Q(employee_name__icontains=search) | Q(employee_code__icontains=search))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(slips, request)

    return paginator.get_paginated_response([payslip_resource(slip) for slip in page])


# -- payslips -----------------------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def payslip(request, payslip_id: int) -> Response:
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.view_payslip(request.user, slip))

    return Response(payslip_resource(slip, with_lines=True))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def adjustments(request, payslip_id: int) -> Response:
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.manage(request.user, slip.school_id))

    form = AdjustmentRequest(data=request.data)
    form.is_valid(raise_exception=True)

    PayslipService.add_adjustment(slip, form.validated_data, request.user, request)

    return Response(payslip_resource(load_payslip(slip.id), with_lines=True), status=status.HTTP_201_CREATED)


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def adjustment(request, payslip_id: int, line_id: int) -> Response:
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.manage(request.user, slip.school_id))

    # Only an adjustment comes off - the basic and the salary components are
    # the salary, changed on the salary and regenerated.
    line = get_object_or_404(PayslipLine, pk=line_id, payslip=slip, source=PayslipLineSource.ADJUSTMENT)

    PayslipService.remove_adjustment(slip, line, request.user, request)

    return Response(payslip_resource(load_payslip(slip.id), with_lines=True))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def pay_payslip(request, payslip_id: int) -> Response:
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.manage(request.user, slip.school_id))

    form = PayRequest(data=request.data, school_today=school_today(slip.school_id))
    form.is_valid(raise_exception=True)

    PayslipService.pay(slip, form.validated_data, request.user, request)

    return Response(payslip_resource(load_payslip(slip.id), with_lines=True))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def payslip_pdf(request, payslip_id: int):
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.view_payslip(request.user, slip))

    response = HttpResponse(payslips.render(slip), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{payslips.file_name(slip)}"'

    return response


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def email_payslip(request, payslip_id: int) -> Response:
    slip = load_payslip(payslip_id)
    authorize(PayrollPolicy.manage(request.user, slip.school_id))

    if slip.payroll_run.status == PayrollRunStatus.DRAFT:
        raise PayrollRunNotFinalized("A draft payslip is not emailed - it can still change.")

    PayslipService.send(slip)

    return Response(payslip_resource(slip, with_lines=True))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_payslips(request) -> Response:
    paginator = LaravelPagination()
    page = paginator.paginate_queryset(PayslipService.mine(request.user), request)

    return paginator.get_paginated_response([payslip_resource(slip) for slip in page])


# -- helpers ------------------------------------------------------------------


def load_run(run_id: int) -> PayrollRun:
    return get_object_or_404(PayrollRun.objects.select_related("school", "generated_by", "finalized_by"), pk=run_id)


def load_payslip(payslip_id: int) -> Payslip:
    return get_object_or_404(
        Payslip.objects.select_related("payroll_run", "school", "staff_profile"), pk=payslip_id
    )


def run_detail(run_id: int) -> dict:
    found = load_run(run_id)
    figures = PayrollRunService.totals([found.id]).get(found.id)
    missing = None

    # What a draft cannot pay yet, and why. A finalized run is history: the
    # list would describe today, not the month it paid.
    if found.status == PayrollRunStatus.DRAFT:
        _, missing = PayrollRunService.eligible(found.school)

    return run_resource(found, figures, missing=missing if missing is not None else [])

