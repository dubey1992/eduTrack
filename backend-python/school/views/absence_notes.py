"""Parents' absence notes, as the school sees them (docs/parent-student-app.md,
F5). The parent's side is in views/family.py.

- GET  absence-notes[?status=sent|acknowledged&class_section_id=] - newest
  first, paginated: the school's notes, or for a teacher the classes they
  keep the register of.
- POST absence-notes/{id}/acknowledge - "seen"; the parent sees it.
- GET  absence-notes/{id}/photo - the doctor's note, to those who may see it.

Whoever may read attendance may read these; a teacher only their own
classes', exactly as the register itself (ClassSectionPolicy).
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import absence_notes, photos
from ..enums import AbsenceNoteStatus, UserRole
from ..models import AbsenceNote, ClassSection
from ..pagination import LaravelPagination
from ..policies import ClassSectionPolicy, authorize, permitted
from ..scope import SchoolScope


def notes_query():
    return AbsenceNote.objects.select_related("student", "submitted_by", "acknowledged_by")


def section_of(note: AbsenceNote) -> ClassSection | None:
    return (
        ClassSection.objects.select_related("school_class").filter(pk=note.student.class_section_id).first()
    )


def may_see(actor, note: AbsenceNote) -> bool:
    section = section_of(note)
    return section is not None and ClassSectionPolicy.view_attendance(actor, section)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    actor = request.user
    authorize(permitted(actor, "attendance"))

    rows = SchoolScope.for_actor(actor).apply_to(notes_query())

    # A teacher keeps the registers of the classes they are class teacher of.
    if actor.role == UserRole.TEACHER:
        rows = rows.filter(student__class_section__class_teacher_id=actor.id)

    wanted = request.query_params.get("status")
    if wanted in AbsenceNoteStatus.values:
        rows = rows.filter(status=wanted)

    section = request.query_params.get("class_section_id")
    if section and section.isdigit():
        rows = rows.filter(student__class_section_id=int(section))

    rows = rows.order_by("status", "-start_date", "-id")
    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)

    return paginator.get_paginated_response([absence_notes.staff_note_resource(note) for note in page])


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def acknowledge(request, note_id: int) -> Response:
    note = get_object_or_404(notes_query(), pk=note_id)
    section = section_of(note)
    authorize(section is not None and ClassSectionPolicy.mark_attendance(request.user, section))

    return Response(absence_notes.staff_note_resource(absence_notes.acknowledge(note, request.user)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def photo(request, note_id: int) -> HttpResponse:
    note = get_object_or_404(notes_query(), pk=note_id)
    authorize(may_see(request.user, note))

    stored = photos.read(note.photo_path) if note.photo_path else None
    if stored is None:
        raise Http404()

    data, content_type = stored
    response = HttpResponse(data, content_type=content_type)
    # Private: never kept by a shared cache.
    response["Cache-Control"] = "private, no-store"
    return response
