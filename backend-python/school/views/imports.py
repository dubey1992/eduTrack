"""Download a template, fill it in, send it back.

Port of BulkImportController. Two endpoints, and the kind of record is a
segment in the path rather than a separate controller per type.
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import csv_export, imports
from ..imports import reader
from ..policies import authorize
from ..scope import SchoolScope
from ..validation import normalise, required

# Two megabytes is several thousand rows of text, well past the 2,000-row
# ceiling the import itself enforces.
MAX_UPLOAD_BYTES = 2048 * 1024


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def template(request, kind: str) -> HttpResponse:
    """The empty spreadsheet, with one example row so nobody has to guess how
    a date or a phone number should look."""
    importer = importer_for(request, kind)

    # The sample row goes through the same cell rules as a report does, which
    # changes nothing for strings and keeps the two writers one writer.
    return csv_export.response(f"{kind}-template.csv", importer.headings(), [importer.sample()])


@api_view(["POST"])
@permission_classes([IsAuthenticated])
# JSON too: a body that is not a form still has to reach the check below and
# be told the file is missing, as Laravel tells it, rather than get a 415.
@parser_classes([MultiPartParser, FormParser, JSONParser])
def store(request, kind: str) -> Response:
    importer = importer_for(request, kind)
    upload = request.FILES.get("file")

    errors = {}

    if upload is None:
        errors["file"] = [required("file")]
    elif upload.size > MAX_UPLOAD_BYTES:
        errors["file"] = ["The file field must not be greater than 2048 kilobytes."]
    elif not str(upload.name).lower().endswith((".csv", ".txt")):
        errors["file"] = ["Upload a CSV file. In Excel, choose File - Save As - CSV."]

    school_id = resolve_school(request, errors)

    if errors:
        raise ValidationError(errors)

    # A bad file raises BulkImportFailed, which the error handler turns into a
    # 422 listing every row that needs fixing.
    return Response(
        reader.run(importer, upload, school_id, request.user),
        status=status.HTTP_201_CREATED,
    )


def resolve_school(request, errors: dict) -> int | None:
    """Laravel's schoolIdRules(), for an upload.

    An actor with one school imports into it and cannot say otherwise.
    Anybody reaching several - a Super Admin, or an admin of a school in a
    group - names the one they mean. A spreadsheet is filed into a branch,
    never into a group.
    """
    scope = SchoolScope.for_actor(request.user)
    requested = normalise(request.data.dict() if hasattr(request.data, "dict") else request.data).get("school_id")

    if scope.default_school_id() is not None:
        return scope.default_school_id()

    if requested is None:
        errors["school_id"] = [required("school_id")]

        return None

    resolved = scope.writable_school_id(SchoolScope.requested_id(requested))

    if resolved is None:
        errors["school_id"] = ["The selected school id is invalid."]

    return resolved


def importer_for(request, kind: str):
    """Resolves the kind of import being asked for, and checks the actor is
    allowed to create that kind of record at all."""
    if not imports.has(kind):
        raise Http404("There is nothing of that kind to import.")

    authorize(imports.policy(kind).create(request.user))

    return imports.importer(kind)
