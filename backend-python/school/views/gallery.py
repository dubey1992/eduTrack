"""Events and photos, as the school posts them (docs/mobile-apps-review.md,
M12, 8.6). The parent's side is in views/family.py.

- GET    gallery-events[?school_id=] - newest first: the school's for its
  admins; school-wide, own classes' and own posts for a teacher.
- POST   gallery-events - {school_id?, class_section_id?, title, event_date, description?}
- GET    gallery-events/{id}
- PATCH  gallery-events/{id} - the same fields; whoever posted it, or an admin.
- DELETE gallery-events/{id} - with its photos.
- POST   gallery-events/{id}/photos - multipart `photo`, one per request.
- GET    gallery-photos/{id}[?size=thumb] - the picture, signed in only.
- DELETE gallery-photos/{id}
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import gallery, photos
from ..enums import UserRole
from ..errors import ApiError
from ..models import GalleryEvent, GalleryPhoto
from ..pagination import LaravelPagination
from ..policies import authorize
from ..scope import SchoolScope

STAFF = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TEACHER, UserRole.HOD)


class SchoolRequired(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "VALIDATION_FAILED"


class EventRequest(serializers.Serializer):
    school_id = serializers.IntegerField(required=False, allow_null=True)
    class_section_id = serializers.IntegerField(required=False, allow_null=True)
    title = serializers.CharField(max_length=500, allow_blank=True)
    event_date = serializers.DateField()
    description = serializers.CharField(max_length=2000, required=False, allow_blank=True, allow_null=True)


def events_query(actor):
    return gallery.visible_events(actor).select_related(
        "class_section__school_class", "posted_by"
    ).prefetch_related("photos")


def event_for(actor, event_id: int) -> GalleryEvent:
    authorize(actor.role in STAFF)
    return get_object_or_404(events_query(actor), pk=event_id)


def serve(photo: GalleryPhoto, thumb: bool) -> HttpResponse:
    stored = photos.read(photo.thumb_path if thumb else photo.file_path)
    if stored is None:
        raise Http404

    data, content_type = stored
    response = HttpResponse(data, content_type=content_type)
    response["Cache-Control"] = "private, max-age=86400"

    return response


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    actor = request.user
    authorize(actor.role in STAFF)

    if request.method == "GET":
        rows = events_query(actor)
        if gallery.is_admin(actor):
            rows = SchoolScope.for_actor(actor).apply_to(rows, request.query_params.get("school_id"))
        rows = rows.order_by("-event_date", "-id")
        paginator = LaravelPagination()
        page = paginator.paginate_queryset(rows, request)
        return paginator.get_paginated_response([gallery.event_resource(e, actor) for e in page])

    form = EventRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    school_id = SchoolScope.for_actor(actor).writable_school_id(data.get("school_id"))
    if school_id is None:
        raise SchoolRequired("Choose the school.", {"errors": {"school_id": ["Choose the school."]}})

    event = gallery.create(actor, school_id, data.get("class_section_id"), data["title"], data["event_date"],
                           data.get("description"), request=request)
    return Response(gallery.event_resource(event_for(actor, event.id), actor), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, event_id: int) -> Response:
    actor = request.user
    event = event_for(actor, event_id)

    if request.method == "GET":
        return Response(gallery.event_resource(event, actor))

    authorize(gallery.may_change(actor, event))
    if request.method == "DELETE":
        gallery.delete(event, request=request)
        return Response(status=status.HTTP_204_NO_CONTENT)

    form = EventRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    gallery.update(actor, event, data.get("class_section_id"), data["title"], data["event_date"],
                   data.get("description"), request=request)
    return Response(gallery.event_resource(event_for(actor, event_id), actor))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser, JSONParser])
def event_photos(request, event_id: int) -> Response:
    actor = request.user
    event = event_for(actor, event_id)
    authorize(gallery.may_change(actor, event))

    gallery.add_photo(actor, event, request.FILES.get("photo"), request=request)
    return Response(gallery.event_resource(event_for(actor, event_id), actor), status=status.HTTP_201_CREATED)


@api_view(["GET", "DELETE"])
@permission_classes([IsAuthenticated])
def photo_detail(request, photo_id: int):
    actor = request.user
    authorize(actor.role in STAFF)
    photo = get_object_or_404(
        GalleryPhoto.objects.select_related("gallery_event"), pk=photo_id,
        gallery_event__in=gallery.visible_events(actor),
    )

    if request.method == "DELETE":
        authorize(gallery.may_remove_photo(actor, photo))
        gallery.remove_photo(photo, request=request)
        return Response(status=status.HTTP_204_NO_CONTENT)

    return serve(photo, request.query_params.get("size") == "thumb")
