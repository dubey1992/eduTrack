"""Student photos in bulk, matched by admission number
(docs/student-photos.md, P2).

Two steps, as with a spreadsheet import: a preview from the file names
alone, then the files themselves in small batches. Who may is whoever may
add students (`StudentPolicy.create`) - School Admins and Super Admins by
default - the same rule as the students spreadsheet (docs/imports.md). A
class teacher sets photos one at a time, never in bulk (D3).

The school is the signed-in person's own; a Super Admin, or an admin
reaching several schools, names one, exactly as for a spreadsheet.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import student_photos
from ..policies import StudentPolicy, authorize
from .imports import resolve_school


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([JSONParser])
def preview(request) -> Response:
    """What each named file would do. JSON: `file_names`, and `school_id`
    where the actor has to say which school."""
    authorize(StudentPolicy.create(request.user))

    errors: dict = {}
    names = request.data.get("file_names") if isinstance(request.data, dict) else None

    if not isinstance(names, list) or not names:
        errors["file_names"] = ["Choose at least one photo."]
    elif len(names) > student_photos.MAX_PREVIEW_NAMES:
        errors["file_names"] = [f"Choose at most {student_photos.MAX_PREVIEW_NAMES} photos at a time."]
    elif not all(isinstance(name, str) and 0 < len(name.strip()) <= 255 for name in names):
        errors["file_names"] = ["Every file name must be text of at most 255 characters."]

    school_id = resolve_school(request, errors)

    if errors:
        raise ValidationError(errors)

    return Response(student_photos.preview(school_id, names))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def store(request) -> Response:
    """Up to ten photos, as `photos`; one result per file."""
    authorize(StudentPolicy.create(request.user))

    errors: dict = {}
    uploads = request.FILES.getlist("photos")

    if not uploads:
        errors["photos"] = ["Choose at least one photo."]
    elif len(uploads) > student_photos.MAX_FILES_PER_BATCH:
        errors["photos"] = [f"Send at most {student_photos.MAX_FILES_PER_BATCH} photos at a time."]

    school_id = resolve_school(request, errors)

    if errors:
        raise ValidationError(errors)

    return Response({"results": student_photos.upload_batch(school_id, uploads, request=request)})
