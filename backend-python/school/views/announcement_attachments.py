"""Files for notices (docs/mobile-apps-review.md, M9, 8.3): adding one
before publishing, taking it back, and reading it.

One file per request; school/notice_attachments.py says why and what is
checked. Reading answers one 404 for "no such file" and "not yours to see",
so nobody learns what another school's notices carry.
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import notice_attachments
from ..models import AnnouncementAttachment
from ..policies import authorize, permitted
from ..requests import php_int
from ..validation import required
from ..scope import SchoolScope


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def collection(request) -> Response:
    """Adds one file (multipart `file`), pending until a publish names it."""
    actor = request.user
    raw_school = request.data.get("school_id")
    requested = None if raw_school in (None, "") else php_int(raw_school)
    school_id = SchoolScope.for_actor(actor).writable_school_id(requested)

    if school_id is None:
        # Somebody who could mean more than one school - a Super Admin, an
        # admin of a branch group - names it, as the publish itself demands.
        raise ValidationError({"school_id": [required("school_id")]})

    authorize(permitted(actor, "announcements", write=True, school_id=school_id))

    try:
        attachment = notice_attachments.upload(request.FILES.get("file"), actor, school_id)
    except notice_attachments.AttachmentRejected as rejected:
        raise ValidationError({"file": [str(rejected)]})

    return Response(notice_attachments.resource(attachment), status=status.HTTP_201_CREATED)


@api_view(["GET", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, attachment_id: int):
    attachment = get_object_or_404(AnnouncementAttachment.objects.select_related("announcement"), pk=attachment_id)

    if not notice_attachments.can_read(request.user, attachment):
        raise Http404

    if request.method == "DELETE":
        # Only a file still waiting: a published notice's files went out with it.
        authorize(attachment.announcement_id is None)
        notice_attachments.remove_pending(attachment)

        return Response(status=status.HTTP_204_NO_CONTENT)

    return serve(attachment)


def serve(attachment: AnnouncementAttachment) -> HttpResponse:
    """The file itself, for a reader already allowed to see it."""
    data = notice_attachments.read(attachment)

    if data is None:
        raise Http404

    response = HttpResponse(data, content_type=attachment.content_type)
    response["Content-Disposition"] = f'inline; filename="{attachment.original_name.replace(chr(34), "")}"'
    response["X-Content-Type-Options"] = "nosniff"
    # Private: a shared cache must never hand one school's file to another.
    response["Cache-Control"] = "private, max-age=86400"

    return response
