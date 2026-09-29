"""Class promotion (docs/promotion.md).

This slice serves the preview alone: a read that answers "what would happen
if this section moved into that year", so the administrator decides with the
roster in front of them rather than after the fact. Nothing here writes, and
the run that does is the next slice.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import promotion
from ..models import ClassSection
from ..policies import PromotionPolicy, authorize
from ..requests import PromotionPreviewRequest


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def preview(request) -> Response:
    form = PromotionPreviewRequest(data=request.query_params)
    form.is_valid(raise_exception=True)

    section = (
        ClassSection.objects.select_related("school_class")
        .get(pk=form.validated_data["class_section_id"])
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
