"""Fee Management: step F1 "Fee Set-up" - fee heads, fee structures for a class
or a bus route with their installments, publishing, and the installment-plan
helper - and step F2 "Dues" - a student's fees statement and the balances
list. See docs/fees.md.

Python only - there is no Laravel twin. Each endpoint asks FeePolicy, then
validates, then hands over to the fee services, which write the change and its
audit row together. Like payroll: a record outside the actor's reach is a
403 (the id exists, and it is not theirs), while another school's id inside
a form - an academic year, a class, a route, a head - is "invalid", exactly
as if it did not exist.

School context: a school-bound actor always acts on their own school. A
Super Admin or Group Admin names one with `school_id` (query on GET, body on
POST), resolved through SchoolScope exactly as payroll resolves it.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..fees import ledger, plan
from ..fees.dues import today_for
from ..fees.requests import (
    BalancesRequest,
    FeeStructureRequest,
    InstallmentPlanRequest,
    StoreFeeHeadRequest,
    UpdateFeeHeadRequest,
    integer,
    raise_if,
    terms_of,
    year_in_scope,
)
from ..fees.resources import (
    balance_row_resource,
    fee_head_resource,
    fee_structure_resource,
    plan_resource,
    statement_resource,
)
from ..fees.service import FeeHeadService, FeeStructureService
from ..models import AcademicYear, FeeHead, FeeStructure, School, Student
from ..pagination import LaravelPagination
from ..policies import FeePolicy, authorize
from ..scope import SchoolScope
from ..validation import does_not_exist, normalise, selected_is_invalid

KINDS = ("class", "route")


# -- fee heads ----------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def heads(request) -> Response:
    if request.method == "POST":
        authorize(FeePolicy.manage_any(request.user))

        form = StoreFeeHeadRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        school_id = form.validated_data["school_id"]
        authorize(FeePolicy.manage(request.user, school_id))

        head = FeeHeadService.create(school_id, form.validated_data["name"], request.user, request)

        return Response(fee_head_resource(FeeHeadService.with_count(head.id)), status=status.HTTP_201_CREATED)

    authorize(FeePolicy.view_any(request.user))

    requested = request.query_params.get("school_id")
    school_id = single_school(request.user, requested)

    if school_id is not None:
        get_object_or_404(School, pk=school_id)
        authorize(FeePolicy.view(request.user, school_id))

    # Not paginated: at most 50 heads per school (fees/service.py MAX_HEADS),
    # and the set-up screen shows them all at once.
    found = FeeHeadService.visible_to(request.user, requested)

    return Response({"data": [fee_head_resource(head) for head in found]})


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def head(request, head_id: int) -> Response:
    found = get_object_or_404(FeeHead, pk=head_id)
    authorize(FeePolicy.manage(request.user, found.school_id))

    if request.method == "DELETE":
        FeeHeadService.delete(found, request.user, request)

        return Response(status=status.HTTP_204_NO_CONTENT)

    form = UpdateFeeHeadRequest(data=request.data)
    form.is_valid(raise_exception=True)

    FeeHeadService.update(found, form.validated_data, request.user, request)

    return Response(fee_head_resource(FeeHeadService.with_count(found.id)))


# -- fee structures -------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def structures(request) -> Response:
    if request.method == "POST":
        authorize(FeePolicy.manage_any(request.user))

        data = FeeStructureRequest(request.data, request.user).store()
        authorize(FeePolicy.manage(request.user, data["academic_year"].school_id))

        structure = FeeStructureService.create(data, request.user, request)

        return Response(
            fee_structure_resource(FeeStructureService.load(structure.id)), status=status.HTTP_201_CREATED
        )

    authorize(FeePolicy.view_any(request.user))

    params = normalise({key: request.query_params.get(key) for key in ("academic_year_id", "school_id", "kind")})
    errors: dict[str, list[str]] = {}
    year = year_in_scope(request.user, params["academic_year_id"], errors, params["school_id"])

    if params["kind"] is not None and params["kind"] not in KINDS:
        errors["kind"] = [selected_is_invalid("kind")]

    raise_if(errors)
    authorize(FeePolicy.view(request.user, year.school_id))

    # Not paginated: one year's fees are bounded by heads (at most 50) times
    # the school's classes and routes, and the set-up grid shows them all.
    found = FeeStructureService.for_year(year, params["kind"])

    return Response({"data": [fee_structure_resource(structure) for structure in found]})


@api_view(["GET", "PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def structure(request, structure_id: int) -> Response:
    found = load_structure(structure_id)

    if request.method == "GET":
        authorize(FeePolicy.view(request.user, found.school_id))

        return Response(fee_structure_resource(found))

    authorize(FeePolicy.manage(request.user, found.school_id))

    if request.method == "DELETE":
        FeeStructureService.delete(found, request.user, request)

        return Response(status=status.HTTP_204_NO_CONTENT)

    data = FeeStructureRequest(request.data, request.user).update(found)
    FeeStructureService.update(found, data, request.user, request)

    return Response(fee_structure_resource(FeeStructureService.load(found.id)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish(request, structure_id: int) -> Response:
    found = load_structure(structure_id)
    authorize(FeePolicy.manage(request.user, found.school_id))

    _, charged = FeeStructureService.publish(found, request.user, request)

    # The structure, plus what publishing charged (F2) - an addition, so a
    # client reading only the structure is unaffected.
    return Response({
        **fee_structure_resource(FeeStructureService.load(found.id)),
        "charged": charged.charged_summary(),
    })


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish_all(request) -> Response:
    """Publishes every draft of one academic year in one school."""
    authorize(FeePolicy.manage_any(request.user))

    data = normalise(request.data) if isinstance(request.data, dict) else {}
    errors: dict[str, list[str]] = {}
    year = year_in_scope(request.user, data.get("academic_year_id"), errors, data.get("school_id"))
    raise_if(errors)

    authorize(FeePolicy.manage(request.user, year.school_id))

    published, charged = FeeStructureService.publish_all(year, request.user, request)
    summary = charged.charged_summary()

    return Response({"published": published, "students": summary["students"], "dues_created": summary["dues_created"]})


# -- what students owe (F2) -----------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def student_fees(request, student_id: int) -> Response:
    """One student's fees statement for a year: every due, cancelled ones
    included (the screen strikes them through), and the totals."""
    authorize(FeePolicy.view_any(request.user))

    student = get_object_or_404(Student.objects.select_related("school"), pk=student_id)
    authorize(FeePolicy.view(request.user, student.school_id))

    raw = normalise({"academic_year_id": request.query_params.get("academic_year_id")})["academic_year_id"]

    if raw is None:
        year = ledger.default_year(student)

        if year is None:
            raise serializers.ValidationError({
                "academic_year_id": ["This school has no academic years yet."]
            })
    else:
        errors: dict[str, list[str]] = {}
        year_id = integer("academic_year_id", raw, errors)
        year = None

        if year_id is not None:
            # Another school's year reads as invalid, like one that does not
            # exist.
            year = AcademicYear.objects.filter(pk=year_id, school_id=student.school_id).first()

            if year is None:
                errors["academic_year_id"] = [does_not_exist("academic_year_id")]

        raise_if(errors)

    found = ledger.statement(student, year, today_for(student.school_id))

    return Response(statement_resource(found))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def balances(request) -> Response:
    """Every student of a year with what they were charged, paid and still
    owe. Paginated; totals worked out in SQL, one statement per page."""
    authorize(FeePolicy.view_any(request.user))

    filters = BalancesRequest(request.query_params, request.user).validate()
    year = filters["academic_year"]
    authorize(FeePolicy.view(request.user, year.school_id))

    rows = ledger.balances(year, filters, today_for(year.school_id))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)

    return paginator.get_paginated_response([balance_row_resource(row) for row in page])


# -- the installment-plan helper ------------------------------------------------


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def installment_plan(request) -> Response:
    """Suggested installments for a frequency. Nothing is saved."""
    authorize(FeePolicy.view_any(request.user))

    data = InstallmentPlanRequest(request.query_params, request.user).validate()
    year = data["academic_year"]
    authorize(FeePolicy.view(request.user, year.school_id))

    terms = terms_of(year)
    count = plan.count_for(data["frequency"], year.start_date, year.end_date, terms)

    if count == 0:
        raise serializers.ValidationError({
            "frequency": [
                "This academic year has no terms yet. Add them under Academic Years, or choose another frequency."
            ]
        })

    # Every installment must be worth at least a cent.
    if data["amount"] * 100 < count:
        raise serializers.ValidationError({
            "amount": [f"The amount is too small to split into {count} installments."]
        })

    rows = plan.suggest(data["frequency"], data["amount"], year.start_date, year.end_date, data["due_day"], terms)

    return Response(plan_resource(rows))


# -- helpers ------------------------------------------------------------------


def single_school(actor, requested) -> int | None:
    """The one school a read is about, when there is one: the school named,
    if the actor can reach it, or the actor's only school. None for an actor
    spanning several who named none (or named one outside their reach, which
    is ignored as SchoolScope.apply_to ignores it)."""
    scope = SchoolScope.for_actor(actor)
    asked = SchoolScope.requested_id(requested)

    if asked is not None and scope.allows(asked):
        return asked

    return scope.default_school_id()


def load_structure(structure_id: int) -> FeeStructure:
    return get_object_or_404(
        FeeStructure.objects.select_related(*FeeStructureService.WITH).prefetch_related("installments"),
        pk=structure_id,
    )
