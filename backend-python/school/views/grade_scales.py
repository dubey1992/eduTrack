"""Grade scales (docs/assessments.md).

CRUD over a school-owned record, with its bands sent inline and replaced as
a set. The rules that decide whether a set of bands is usable - covering 0
to 100, not overlapping - live in the form, because they are answers about
the request.

Deleting is refused while a scale is the school's default and another exists,
so a school is never left with scales and no default.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import GradeScale
from ..pagination import LaravelPagination
from ..policies import GradeScalePolicy, authorize
from ..requests import StoreGradeScaleRequest, UpdateGradeScaleRequest
from ..resources import grade_scale_resource
from ..services import GradeScaleService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(GradeScalePolicy.view_any(request.user))

    scales = GradeScaleService.visible_to(request.user, {"school_id": request.query_params.get("school_id")})

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(scales, request)

    return paginator.get_paginated_response([grade_scale_resource(scale) for scale in page])


def store(request) -> Response:
    authorize(GradeScalePolicy.create(request.user))

    form = StoreGradeScaleRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    scale = GradeScaleService.create(form.validated_data, request.user)

    return Response(grade_scale_resource(reload(scale.id)), status=status.HTTP_201_CREATED)


@api_view(["GET", "PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, scale_id: int) -> Response:
    scale = load(scale_id)

    if request.method == "PUT":
        return update(request, scale)

    if request.method == "DELETE":
        return destroy(request, scale)

    authorize(GradeScalePolicy.view(request.user, scale))

    return Response(grade_scale_resource(scale))


def update(request, scale: GradeScale) -> Response:
    """PUT rather than PATCH: the bands are replaced as a whole set, so this
    is not a partial edit however the name is sent."""
    authorize(GradeScalePolicy.update(request.user, scale))

    form = UpdateGradeScaleRequest(data=request.data, actor=request.user, scale=scale)
    form.is_valid(raise_exception=True)

    GradeScaleService.update(scale, form.validated_data)

    return Response(grade_scale_resource(reload(scale.id)))


def destroy(request, scale: GradeScale) -> Response:
    authorize(GradeScalePolicy.delete(request.user, scale))

    GradeScaleService.delete(scale)

    return Response(status=status.HTTP_204_NO_CONTENT)


def load(scale_id: int) -> GradeScale:
    return get_object_or_404(GradeScale.objects.select_related("school").prefetch_related("bands"), pk=scale_id)


def reload(scale_id: int) -> GradeScale:
    return GradeScale.objects.select_related("school").prefetch_related("bands").get(pk=scale_id)
