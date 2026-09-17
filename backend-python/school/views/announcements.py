"""Announcements: the compose flow's preview, publishing, and the list of what
has gone out. Reading one as a recipient is the inbox.

Port of AnnouncementController. Two orders of checks to keep:

- **Publishing** authorizes before it validates, the way its form request
  does - and authorizes against the audience asked for, so a head of
  department naming another department is a 403 before any field is read.
  An audience that is not one at all falls back to the plain role gate, so it
  can still be reported as a 422.
- **The preview** has no form: an audience or channel that is not one is a
  bare 422 with the framework's generic sentence, and a target is cast the
  way PHP casts it.

The preview used to name another school's class or department when handed
its id; the label is now looked up inside the school being announced to only.
Fixed on both backends in the same change.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import SchoolClock
from ..enums import AnnouncementAudience, AnnouncementChannels
from ..errors import UnprocessableRequest
from ..models import Announcement
from ..pagination import LaravelPagination
from ..policies import AnnouncementPolicy, authorize
from ..requests import PublishAnnouncementRequest, php_int
from ..validation import normalise
from ..resources import announcement_resource
from ..scope import SchoolScope
from ..services import AnnouncementService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return publish(request)

    authorize(AnnouncementPolicy.view_any(request.user))

    # Trimmed, and blank meaning absent - what Laravel's middleware does to
    # every input before a controller reads it.
    query = normalise(request.query_params.dict())

    found = AnnouncementService.visible_to(
        request.user,
        {key: query.get(key) for key in ("school_id", "audience_type", "q", "active_only")},
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([announcement_resource(row) for row in page])


def publish(request) -> Response:
    actor = request.user
    data = normalise(request.data)
    audience = data.get("audience_type")

    raw_school = data.get("school_id")
    requested = None if raw_school in (None, "") else php_int(raw_school)
    school_id = SchoolScope.for_actor(actor).writable_school_id(requested)

    if audience in AnnouncementAudience.values:
        raw_target = data.get("audience_id")
        target = None if raw_target is None else php_int(raw_target)

        authorize(AnnouncementPolicy.publish(actor, audience, target, school_id))
    else:
        authorize(AnnouncementPolicy.view_any(actor))

    # "Not in the past" on the school's calendar.
    today = SchoolClock.for_scope(actor, requested).now().date()

    form = PublishAnnouncementRequest(data=request.data, actor=actor, school_today=today)
    form.is_valid(raise_exception=True)

    announcement = AnnouncementService.publish(form.validated_data, actor)

    return Response(announcement_resource(announcement), status=status.HTTP_201_CREATED)


def live(announcement_id: int):
    """Not found once deleted, as a soft-deleted Eloquent model is."""
    return get_object_or_404(
        Announcement.objects.select_related("school", "published_by").filter(deleted_at__isnull=True),
        pk=announcement_id,
    )


@api_view(["GET", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, announcement_id: int) -> Response:
    announcement = live(announcement_id)

    if request.method == "DELETE":
        authorize(AnnouncementPolicy.delete(request.user, announcement))

        AnnouncementService.delete(announcement)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(AnnouncementPolicy.view(request.user, announcement))

    return Response(announcement_resource(announcement))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def preview(request) -> Response:
    """How many people an audience would reach, so the compose form can say
    "goes to 312 people" before anything is sent."""
    actor = request.user

    authorize(AnnouncementPolicy.view_any(actor))

    query = normalise(request.query_params.dict())
    audience = query.get("audience_type")
    channels = query.get("channels")

    if audience not in AnnouncementAudience.values or channels not in AnnouncementChannels.values:
        raise UnprocessableRequest()

    raw_school = query.get("school_id")
    school_id = int(actor.school_id or 0) if raw_school is None else php_int(raw_school)

    raw_target = query.get("audience_id")
    target = None if raw_target is None else php_int(raw_target)

    authorize(AnnouncementPolicy.publish(actor, audience, target, school_id))

    return Response(
        {
            **AnnouncementService.count_recipients(school_id, audience, target, channels),
            "audience_label": AnnouncementService.audience_label(school_id, audience, target),
        }
    )
