"""Academic terms (docs/assessments.md).

Ordinary CRUD over a school-owned record, with one thing worth knowing: the
year a term belongs to is fixed at creation. Moving a term to another year
would move every result filed under it, so `PATCH` does not accept the field
and the form does not offer it.

The rules that make a term legal - inside its year, not overlapping a sibling,
one name and one sequence number per year - live in the form, because they are
answers about the request rather than about the record.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import AcademicTerm
from ..pagination import LaravelPagination
from ..policies import AcademicTermPolicy, authorize
from ..requests import StoreAcademicTermRequest, UpdateAcademicTermRequest
from ..resources import academic_term_resource
from ..services import AcademicTermService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(AcademicTermPolicy.view_any(request.user))

    terms = AcademicTermService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "academic_year_id": request.query_params.get("academic_year_id"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(terms, request)

    return paginator.get_paginated_response([academic_term_resource(term) for term in page])


def store(request) -> Response:
    authorize(AcademicTermPolicy.create(request.user))

    form = StoreAcademicTermRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    term = AcademicTermService.create(form.validated_data, request.user)

    return Response(academic_term_resource(reload(term.id)), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, term_id: int) -> Response:
    term = load(term_id)

    if request.method == "PATCH":
        return update(request, term)

    if request.method == "DELETE":
        return destroy(request, term)

    authorize(AcademicTermPolicy.view(request.user, term))

    return Response(academic_term_resource(term))


def update(request, term: AcademicTerm) -> Response:
    authorize(AcademicTermPolicy.update(request.user, term))

    form = UpdateAcademicTermRequest(data=request.data, actor=request.user, term=term)
    form.is_valid(raise_exception=True)

    AcademicTermService.update(term, form.validated_data)

    return Response(academic_term_resource(reload(term.id)))


def destroy(request, term: AcademicTerm) -> Response:
    authorize(AcademicTermPolicy.delete(request.user, term))

    AcademicTermService.delete(term)

    return Response(status=status.HTTP_204_NO_CONTENT)


def load(term_id: int) -> AcademicTerm:
    return get_object_or_404(AcademicTerm.objects.select_related("academic_year"), pk=term_id)


def reload(term_id: int) -> AcademicTerm:
    return AcademicTerm.objects.select_related("academic_year").get(pk=term_id)
