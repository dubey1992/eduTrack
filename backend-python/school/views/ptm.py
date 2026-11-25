"""Parent-teacher meetings, as the school runs them (docs/mobile-apps-review.md,
M12, 8.4). The parent's side is in views/family.py.

- GET   ptm-meetings[?school_id=&past=1] - meetings ahead (or past), soonest
  first: the school's for its admins; a class teacher's own classes' for them.
- POST  ptm-meetings - {school_id?, title, meeting_date, note?, section_ids}; admins.
- GET   ptm-meetings/{id}
- PATCH ptm-meetings/{id} - the same fields; admins.
- POST  ptm-meetings/{id}/cancel - admins; the parents who booked are told.
- GET   ptm-meetings/{id}/sections/{section_id}/slots - the class's slots and who booked.
- POST  ptm-meetings/{id}/sections/{section_id}/slots - {starts_at, ends_at, slot_minutes}.
- DELETE ptm-slots/{id}
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import ptm
from ..enums import UserRole
from ..errors import ApiError
from ..models import ClassSection, PtmMeeting, PtmSlot
from ..pagination import LaravelPagination
from ..policies import authorize
from ..scope import SchoolScope

STAFF = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TEACHER, UserRole.HOD)


class SchoolRequired(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "VALIDATION_FAILED"


class MeetingRequest(serializers.Serializer):
    school_id = serializers.IntegerField(required=False, allow_null=True)
    title = serializers.CharField(max_length=500, allow_blank=True)
    meeting_date = serializers.DateField()
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True, allow_null=True)
    section_ids = serializers.ListField(child=serializers.IntegerField(), allow_empty=True, max_length=500)


class SlotsRequest(serializers.Serializer):
    starts_at = serializers.CharField(max_length=8)
    ends_at = serializers.CharField(max_length=8)
    slot_minutes = serializers.IntegerField()


def visible_meetings(actor):
    """What this person may see: the school's meetings for an admin; for a
    teacher, the meetings one of their classes takes part in."""
    rows = PtmMeeting.objects.all()
    if ptm.is_admin(actor):
        return SchoolScope.for_actor(actor).apply_to(rows)

    return rows.filter(
        school_id=actor.school_id, sections__class_section__class_teacher_id=actor.id
    ).distinct()


def meeting_for(actor, meeting_id: int) -> PtmMeeting:
    authorize(actor.role in STAFF)
    return get_object_or_404(visible_meetings(actor), pk=meeting_id)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    actor = request.user
    authorize(actor.role in STAFF)

    if request.method == "GET":
        rows = visible_meetings(actor)
        if ptm.is_admin(actor):
            rows = SchoolScope.for_actor(actor).apply_to(rows, request.query_params.get("school_id"))
        today = ptm.today_at(actor.school_id) if actor.school_id else None
        if today is not None:
            past = request.query_params.get("past") in ("1", "true")
            rows = rows.filter(meeting_date__lt=today) if past else rows.filter(meeting_date__gte=today)
            rows = rows.order_by("-meeting_date", "-id") if past else rows.order_by("meeting_date", "id")
        else:
            rows = rows.order_by("-meeting_date", "-id")
        paginator = LaravelPagination()
        page = paginator.paginate_queryset(rows, request)
        return paginator.get_paginated_response([ptm.meeting_resource(m, actor) for m in page])

    authorize(ptm.is_admin(actor))
    form = MeetingRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    school_id = SchoolScope.for_actor(actor).writable_school_id(data.get("school_id"))
    if school_id is None:
        raise SchoolRequired("Choose the school.", {"errors": {"school_id": ["Choose the school."]}})

    meeting = ptm.create_meeting(
        actor, school_id, data["title"], data["meeting_date"], data.get("note"), data["section_ids"], request=request
    )
    return Response(ptm.meeting_resource(meeting, actor), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, meeting_id: int) -> Response:
    actor = request.user
    meeting = meeting_for(actor, meeting_id)

    if request.method == "GET":
        return Response(ptm.meeting_resource(meeting, actor))

    authorize(ptm.may_manage_meeting(actor, meeting))
    form = MeetingRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    meeting = ptm.update_meeting(
        meeting, data["title"], data["meeting_date"], data.get("note"), data["section_ids"], request=request
    )
    return Response(ptm.meeting_resource(meeting, actor))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def cancel(request, meeting_id: int) -> Response:
    actor = request.user
    meeting = meeting_for(actor, meeting_id)
    authorize(ptm.may_manage_meeting(actor, meeting))

    return Response(ptm.meeting_resource(ptm.cancel_meeting(meeting, request=request), actor))


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def section_slots(request, meeting_id: int, section_id: int) -> Response:
    actor = request.user
    meeting = meeting_for(actor, meeting_id)
    section = get_object_or_404(ClassSection, pk=section_id, school_class__school_id=meeting.school_id)
    authorize(ptm.may_manage_section(actor, meeting, section))

    if request.method == "POST":
        form = SlotsRequest(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data
        ptm.open_slots(meeting, section, actor, data["starts_at"], data["ends_at"], data["slot_minutes"],
                       request=request)

    slots = (
        PtmSlot.objects.select_related("teacher_user", "booking__student", "booking__booked_by")
        .filter(ptm_meeting_id=meeting.id, class_section_id=section.id)
        .order_by("starts_at")
    )
    return Response(
        {"data": [ptm.staff_slot_resource(s) for s in slots]},
        status=status.HTTP_201_CREATED if request.method == "POST" else status.HTTP_200_OK,
    )


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def slot_detail(request, slot_id: int) -> Response:
    actor = request.user
    authorize(actor.role in STAFF)
    slot = get_object_or_404(
        PtmSlot.objects.select_related("ptm_meeting", "class_section"),
        pk=slot_id, ptm_meeting__in=visible_meetings(actor),
    )
    authorize(ptm.may_manage_section(actor, slot.ptm_meeting, slot.class_section))

    ptm.remove_slot(slot, request=request)
    return Response(status=status.HTTP_204_NO_CONTENT)
