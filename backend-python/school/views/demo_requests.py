"""Demo requests: the marketing page's "Request a Demo" form, and the Super
Admin's list of them (decided 2026-10-29).

Built like early access, which it sits beside: asking is public and
throttled - it is how a school with no account gets in touch - and reading
or updating the list is the Super Admin's alone.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import NotAuthenticated
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import DemoRequest
from ..pagination import LaravelPagination
from ..policies import authorize
from ..requests import ReviewDemoRequest, StoreDemoRequest
from ..resources import demo_request_resource
from ..services import DemoRequestService
from ..throttling import DemoRequestThrottle
from .early_access import is_super_admin


@api_view(["GET", "POST"])
@permission_classes([])
@throttle_classes([DemoRequestThrottle])
def collection(request) -> Response:
    if request.method == "POST":
        form = StoreDemoRequest(data=request.data)
        form.is_valid(raise_exception=True)

        DemoRequestService.record(form.validated_data)

        # The same answer whether this was a new request or a repeat.
        return Response(
            {"message": "Thanks - we will be in touch to confirm a time for your demo."},
            status=status.HTTP_201_CREATED,
        )

    if request.user is None:
        raise NotAuthenticated()

    authorize(is_super_admin(request.user))

    found = DemoRequestService.visible_to({
        "status": request.query_params.get("status"),
        "q": (request.query_params.get("q") or "").strip() or None,
    })

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([demo_request_resource(row) for row in page])


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, request_id: int) -> Response:
    authorize(is_super_admin(request.user))
    found = get_object_or_404(DemoRequest.objects.select_related("reviewed_by"), pk=request_id)

    if request.method == "PATCH":
        form = ReviewDemoRequest(data=request.data)
        form.is_valid(raise_exception=True)

        found = DemoRequestService.review(found, form.validated_data, request.user)

    return Response(demo_request_resource(found))
