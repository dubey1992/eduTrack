"""Files a notice carries (docs/mobile-apps-review.md, M9, 8.3).

Decided by the owner 2026-11-24: up to three per notice, PDF, JPEG or PNG,
5 MB each.

**One file per request, before the notice is published.** The shared host
runs the API as CGI and does badly with one large request, so each file is
uploaded on its own and waits "pending" - no announcement yet, readable
only by whoever uploaded it - until the publish names it. A pending file
never published is cleared after a day, the next time that person uploads.

**Nothing is trusted from the client.** An image is decoded and re-encoded
like a photo (school/photos.py), which drops whatever rode along in it. A
PDF is recognised by its first bytes, never by its name or the type the
browser claims, and is served back as a download-or-view PDF and nothing
else.

**Who reads a file:** the notice's publishers (whoever may see it in the
Announcements list) and the people it reached in the app - a staff inbox or
a parent's Family app. SMS and WhatsApp carry the words only.
"""

from __future__ import annotations

import datetime as dt
import os
import re

from django.db import transaction
from django.utils import timezone

from . import audit, photos
from .models import Announcement, AnnouncementAttachment, User

MAX_FILES = 3
MAX_BYTES = 5 * 1024 * 1024
# A notice's picture is a poster or a scanned page, so far larger than a face.
IMAGE_MAX_SIDE = 2000
FOLDER = "notice-attachments"
PENDING_FOR = dt.timedelta(days=1)
# Unpublished uploads one person may hold at once, so a stuck form cannot
# fill the disk.
MAX_PENDING = 10

PDF = "application/pdf"
IMAGE_TYPES = {"jpg": "image/jpeg", "png": "image/png"}


class AttachmentRejected(Exception):
    """The file is not one a notice may carry. The message is for the person."""


def upload(file, actor: User, school_id: int) -> AnnouncementAttachment:
    """Checks and stores one file, pending until a publish names it."""
    clear_stale(actor)

    if AnnouncementAttachment.objects.filter(uploaded_by_id=actor.id, announcement__isnull=True).count() >= MAX_PENDING:
        raise AttachmentRejected("Publish or remove the files already added before adding more.")

    data, content_type, extension = _checked(file)
    path = photos.store(data, extension, folder=FOLDER)
    now = timezone.now()

    return AnnouncementAttachment.objects.create(
        school_id=school_id,
        uploaded_by_id=actor.id,
        file_path=path,
        original_name=_display_name(file.name, extension),
        content_type=content_type,
        size_bytes=len(data),
        created_at=now,
        updated_at=now,
    )


def _checked(file) -> tuple[bytes, str, str]:
    """(bytes to keep, content type, extension), or AttachmentRejected."""
    if file is None:
        raise AttachmentRejected("Choose a file to attach.")

    if file.size > MAX_BYTES:
        raise AttachmentRejected("Each file must be 5 MB or smaller.")

    head = file.read(5)
    file.seek(0)

    if head == b"%PDF-":
        return file.read(), PDF, "pdf"

    try:
        data, extension = photos.prepare(file, max_side=IMAGE_MAX_SIDE, max_bytes=MAX_BYTES, noun="file")
    except photos.PhotoRejected:
        raise AttachmentRejected("Attach a PDF, JPEG or PNG file.")

    return data, IMAGE_TYPES[extension], extension


def _display_name(name: str | None, extension: str) -> str:
    """The name shown beside the file: the uploader's own, without any
    folder, with the extension the stored file really has."""
    base = os.path.basename((name or "").replace("\\", "/"))
    stem = re.sub(r"[\x00-\x1f]", "", os.path.splitext(base)[0]).strip() or "Attachment"

    return f"{stem[:140]}.{extension}"


def clear_stale(actor: User) -> None:
    """Forgets this person's uploads that were never published."""
    stale = AnnouncementAttachment.objects.filter(
        uploaded_by_id=actor.id, announcement__isnull=True, created_at__lt=timezone.now() - PENDING_FOR
    )

    for row in stale:
        photos.remove(row.file_path)

    stale.delete()


def pending_of(actor: User, school_id: int, ids) -> list[AnnouncementAttachment]:
    """The named uploads, if every one is this person's, unpublished and for
    this school - else None for the request to refuse."""
    rows = list(
        AnnouncementAttachment.objects.filter(
            pk__in=ids, uploaded_by_id=actor.id, school_id=school_id, announcement__isnull=True
        )
    )

    return rows if len(rows) == len(set(ids)) else None


def attach(announcement: Announcement, ids: list[int]) -> None:
    """Hands the uploads to the published notice, in the order given. Runs
    inside the publish's transaction."""
    if not ids:
        return

    order = {attachment_id: position for position, attachment_id in enumerate(ids)}
    rows = AnnouncementAttachment.objects.select_for_update().filter(pk__in=ids, announcement__isnull=True)

    for row in rows:
        row.announcement = announcement
        row.sort_order = order[row.id]
        row.updated_at = timezone.now()
        row.save(update_fields=["announcement", "sort_order", "updated_at"])

    audit.record(
        action="announcement.attachments_added", module="announcements", entity_type="announcement",
        entity_id=announcement.id, school_id=announcement.school_id,
        new={"attachments": [row.original_name for row in sorted(rows, key=lambda r: r.sort_order)]},
    )


def remove_pending(attachment: AnnouncementAttachment) -> None:
    with transaction.atomic():
        attachment.delete()

    photos.remove(attachment.file_path)


def can_read(actor: User, attachment: AnnouncementAttachment) -> bool:
    """The uploader while it waits; once published, whoever may see the
    notice in Announcements or received it in the app."""
    from .policies import AnnouncementPolicy
    from .services import MessageService

    if attachment.announcement_id is None:
        return attachment.uploaded_by_id == actor.id

    announcement = attachment.announcement

    if announcement.deleted_at is not None:
        return False

    if AnnouncementPolicy.view(actor, announcement):
        return True

    return MessageService.inbox_of(actor).filter(announcement_id=announcement.id).exists()


def read(attachment: AnnouncementAttachment) -> bytes | None:
    stored = photos.read(attachment.file_path)

    return None if stored is None else stored[0]


def resource(attachment: AnnouncementAttachment, family: bool = False) -> dict:
    """[family]: the address the Family app reads it from - a parent's
    session reaches only the Family API."""
    return {
        "id": attachment.id,
        "name": attachment.original_name,
        "content_type": attachment.content_type,
        "size_bytes": attachment.size_bytes,
        "url": f"/family/attachments/{attachment.id}" if family else f"/announcement-attachments/{attachment.id}",
    }


def of_announcements(announcement_ids, family: bool = False) -> dict[int, list[dict]]:
    """Every listed notice's files, in one query, for a page of a list."""
    found: dict[int, list[dict]] = {}

    for row in AnnouncementAttachment.objects.filter(announcement_id__in=set(announcement_ids)).order_by(
        "sort_order", "id"
    ):
        found.setdefault(row.announcement_id, []).append(resource(row, family))

    return found
