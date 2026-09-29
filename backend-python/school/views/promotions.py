"""Class promotion (docs/promotion.md).

Three endpoints: the preview, which answers "what would happen if this
section moved into that year" and writes nothing; the run, which does it in
one transaction; and the history, which reads back what was done.

The school always comes from the section the actor named, never from the
request, so an id swapped in a query string reaches a 403 rather than
another school's class.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import promotion
from ..models import ClassSection
from ..pagination import LaravelPagination
from ..policies import PromotionPolicy, authorize
from ..requests import PromotionPreviewRequest, RunPromotionRequest
from ..resources import promotion_batch_resource, promotion_outcome_resource


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    """Past runs. A Super Admin reads any school's promotion history and runs
    none of it, which is why this asks a different question of the policy."""
    authorize(PromotionPolicy.view_any(request.user))

    batches = promotion.history(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "academic_year_id": request.query_params.get("academic_year_id"),
            "class_section_id": request.query_params.get("class_section_id"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(batches, request)

    return paginator.get_paginated_response([promotion_batch_resource(batch) for batch in page])


def store(request) -> Response:
    form = RunPromotionRequest(data=request.data)
    form.is_valid(raise_exception=True)

    section = ClassSection.objects.select_related("school_class__academic_year").get(
        pk=form.validated_data["class_section_id"]
    )

    authorize(PromotionPolicy.run(request.user, promotion.school_id_of(section)))

    batch = promotion.run(section, form.validated_data, request.user)

    return Response(promotion_batch_resource(batch), status=status.HTTP_201_CREATED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def detail(request, batch_id: int) -> Response:
    """One run, with what it did to each student."""
    batch = get_object_or_404(promotion.PromotionRun.with_names(), pk=batch_id)

    authorize(PromotionPolicy.view(request.user, batch.school_id))

    landings = promotion.landing_of(batch)

    return Response(
        {
            **promotion_batch_resource(batch),
            "students": [
                promotion_outcome_resource(row, landings.get(row.student_id))
                for row in promotion.outcomes_of(batch)
            ],
        }
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def preview(request) -> Response:
    form = PromotionPreviewRequest(data=request.query_params)
    form.is_valid(raise_exception=True)

    section = ClassSection.objects.select_related("school_class__academic_year").get(
        pk=form.validated_data["class_section_id"]
    )

    # The school comes from the section the actor named, never from the
    # request: a preview of another school's class is a 403 whatever ids are
    # sent with it.
    authorize(PromotionPolicy.preview(request.user, promotion.school_id_of(section)))

    return Response(
        promotion.preview(
            section,
            form.validated_data["to_academic_year_id"],
            form.validated_data.get("to_class_section_id"),
        )
    )
