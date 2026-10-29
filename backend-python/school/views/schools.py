"""Schools: onboarding them, and the branch pickers that read them.

Port of SchoolController. Schools are platform records - only a Super Admin
creates or edits one - but a Group Admin reads their own group, which is what
fills the "which branch?" picker the client shows everywhere.

No delete, and not by omission: erasing a school's records is not something a
school management system should offer. Deactivating is as far as any caller
can go.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import SchoolStatus
from ..models import EarlyAccessRequest, School
from ..pagination import LaravelPagination
from ..policies import SchoolPolicy, authorize
from ..requests import StoreSchoolRequest, UpdateSchoolRequest
from ..resources import school_resource
from ..services import EarlyAccessService, SchoolService

# As many pins as a map is worth drawing. A platform with more schools than
# this has outgrown one map of all of them, and the list screen is still
# there; saying so beats quietly dropping the tail.
MAP_LIMIT = 500


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def _filters(request) -> dict:
    """What the list and the map are both narrowed by."""
    return {key: (request.query_params.get(key) or "").strip() for key in ("q", "status", "category")}


def index(request) -> Response:
    authorize(SchoolPolicy.view_any(request.user))

    schools = SchoolService.visible_to(request.user, _filters(request))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(schools, request)

    return paginator.get_paginated_response(
        [school_resource(school, branch_count=school.branch_count) for school in page]
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def locations(request) -> Response:
    """Every school this actor may see, as pins (docs/maps.md, M1d).

    Separate from the list because a map is not a page of twenty: a pin
    missing because it was on page four is a school that looks like it does
    not exist. So this answers in one go, with only what a pin needs.

    **Schools with no coordinates come back too.** They are the ones
    somebody has to go and place, and a map that silently omitted them
    would hide exactly the work it exists to prompt.

    It takes the list's own search and status filter, because a filtered
    list beside an unfiltered map is two answers to the same question.
    """
    authorize(SchoolPolicy.view_any(request.user))

    # One row more than the cap, so "there are more" is known without
    # counting the table a second time. The probe row is dropped before
    # anything is built from it.
    # `scoped` rather than `visible_to`: the same schools by the same rule,
    # without the branch count and parent join a pin never reads.
    found = list(
        SchoolService.scoped(request.user, _filters(request))
        .only("id", "name", "parent_school_id", "status", "city", "latitude", "longitude")[: MAP_LIMIT + 1]
    )
    more = len(found) > MAP_LIMIT
    placed, unplaced = [], []

    for school in found[:MAP_LIMIT]:
        if school.latitude is None or school.longitude is None:
            unplaced.append({"id": school.id, "name": school.name})
            continue

        placed.append(
            {
                "id": school.id,
                "name": school.name,
                "parent_school_id": school.parent_school_id,
                "is_branch": school.parent_school_id is not None,
                "status": school.status,
                "city": school.city,
                # Strings, like every other coordinate in this API: a
                # decimal(10,7) through a float loses the seventh place.
                "latitude": str(school.latitude),
                "longitude": str(school.longitude),
            }
        )

    return Response({"placed": placed, "unplaced": unplaced, "more_than_shown": more})


def store(request) -> Response:
    authorize(SchoolPolicy.create(request.user))

    form = StoreSchoolRequest(data=request.data)
    form.is_valid(raise_exception=True)

    data = dict(form.validated_data)
    early_access_request_id = data.pop("early_access_request_id", None)
    admin = data.pop("admin", None)

    school = SchoolService.create(data, admin=admin, actor=request.user)

    # Closing the loop: the signup request records the school it became, which
    # is the only way "Converted" can be true rather than remembered.
    if early_access_request_id is not None:
        EarlyAccessService.mark_converted(
            get_object_or_404(EarlyAccessRequest, pk=early_access_request_id),
            school,
            request.user,
        )

    return Response(school_resource(school), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, school_id: int) -> Response:
    school = get_object_or_404(School.objects.select_related("parent_school"), pk=school_id)

    if request.method == "PATCH":
        return update(request, school)

    authorize(SchoolPolicy.view(request.user, school))

    return Response(school_resource(school, branch_count=SchoolService.branch_count(school)))


def update(request, school: School) -> Response:
    authorize(SchoolPolicy.update(request.user, school))

    form = UpdateSchoolRequest(data=request.data, school=school)
    form.is_valid(raise_exception=True)

    SchoolService.update(school, form.validated_data)

    return Response(school_resource(reload(school.id)))


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def activate(request, school_id: int) -> Response:
    return set_status(request, school_id, SchoolStatus.ACTIVE)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def deactivate(request, school_id: int) -> Response:
    return set_status(request, school_id, SchoolStatus.INACTIVE)


def set_status(request, school_id: int, status_value: str) -> Response:
    school = get_object_or_404(School, pk=school_id)

    authorize(SchoolPolicy.set_status(request.user, school))

    SchoolService.set_status(school, status_value)

    return Response(school_resource(reload(school.id)))


def reload(school_id: int) -> School:
    """Reads the school back with the parent loaded, so a write answers the
    same shape a read does."""
    return School.objects.select_related("parent_school").get(pk=school_id)
