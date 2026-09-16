"""The week's grid.

Port of TimetableController. Three endpoints: read the grid, write one cell,
remove one cell.

The grid is read one of two ways - by class section or by teacher - and which
one the caller meant is the request's business. What this module adds is the
check that the class or the teacher asked for is actually theirs to look at,
and it answers **404 rather than 403** when it is not: the id came from a
query string, and telling a stranger that section 41 exists but is not theirs
is more than they asked and more than they should get.

Not paginated. A week is five days by eight or nine periods, and a paging
control on forty rows is furniture nobody uses - the same call the periods
list makes.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import NotFound
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import ClassSection, TimetableEntry, User
from ..policies import TimetableEntryPolicy, authorize
from ..requests import TimetableGridRequest, UpsertTimetableEntryRequest
from ..resources import timetable_entry_resource
from ..scope import SchoolScope
from ..services import TimetableService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return upsert(request)

    form = TimetableGridRequest(data=request.query_params.dict(), actor=request.user)
    form.is_valid(raise_exception=True)

    authorize(TimetableEntryPolicy.view_any(request.user))

    entries = grid_for(request.user, form.validated_data)

    return Response([timetable_entry_resource(entry) for entry in entries])


def grid_for(actor, asked: dict):
    """Whichever slice was asked for, once the target is known to be theirs."""
    if asked.get("class_section_id") is not None:
        section = get_object_or_404(
            ClassSection.objects.select_related("school_class"),
            pk=asked["class_section_id"],
        )

        assert_same_school(actor, section.school_class.school_id)

        return TimetableService.for_class_section(section.id)

    teacher = get_object_or_404(User, pk=asked["teacher_id"])

    assert_same_school(actor, teacher.school_id)

    return TimetableService.for_teacher(teacher.id)


def assert_same_school(actor, school_id) -> None:
    """A 404, not a 403, and deliberately.

    The id was named in a query string, so an actor who may not see it should
    learn nothing about it - not even that it is real.
    """
    if not SchoolScope.for_actor(actor).allows(school_id):
        raise NotFound()


def upsert(request) -> Response:
    form = UpsertTimetableEntryRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    school_id = form.validated_data["school_id"]

    authorize(TimetableEntryPolicy.manage(request.user, school_id))

    entry = TimetableService.upsert(form.validated_data)

    return Response(timetable_entry_resource(entry), status=status.HTTP_201_CREATED)


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def entry(request, entry_id: int) -> Response:
    found = get_object_or_404(TimetableEntry, pk=entry_id)

    authorize(TimetableEntryPolicy.delete(request.user, found))

    TimetableService.delete(found)

    return Response(status=status.HTTP_204_NO_CONTENT)
